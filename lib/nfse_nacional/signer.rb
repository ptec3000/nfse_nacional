require "base64"
require "openssl"
require "nokogiri"

module NfseNacional
  class Signer
    class Invalid < StandardError; end

    DS = "http://www.w3.org/2000/09/xmldsig#"
    NS = {"ds" => DS}.freeze
    # perfil de assinatura aceito pela Sefin em produção; o xmldsig publicado no pacote de schemas fixa SHA-1 — se a homologação recusar, trocar aqui
    ALGORITHMS = {
      canonicalization: "http://www.w3.org/2001/10/xml-exc-c14n#WithComments",
      signature: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
      enveloped_transform: "#{DS}enveloped-signature",
      digest: "http://www.w3.org/2001/04/xmlenc#sha256"
    }.freeze

    def initialize(certificado)
      @certificado = certificado
    end

    def sign(xml, node:)
      doc, target = self.class.send(:document_and_target, xml, node)
      target.parent.xpath("ds:Signature", NS).remove
      # Build in the final namespace context before canonicalizing SignedInfo.
      signature = Nokogiri::XML::Builder.new do |builder|
        builder.Signature(xmlns: DS) do
          builder.SignedInfo do
            builder.CanonicalizationMethod(Algorithm: ALGORITHMS[:canonicalization])
            builder.SignatureMethod(Algorithm: ALGORITHMS[:signature])
            builder.Reference(URI: "##{target["Id"]}") do
              builder.Transforms do
                builder.Transform(Algorithm: ALGORITHMS[:enveloped_transform])
                builder.Transform(Algorithm: ALGORITHMS[:canonicalization])
              end
              builder.DigestMethod(Algorithm: ALGORITHMS[:digest])
              builder.DigestValue
            end
          end
          builder.SignatureValue
          builder.KeyInfo do
            builder.X509Data {builder.X509Certificate(Base64.strict_encode64(@certificado.certificate.to_der))}
          end
        end
      end.doc.root
      target.parent.add_child(signature)
      signature = target.parent.at_xpath("ds:Signature", NS)
      signature.at_xpath("ds:SignedInfo/ds:Reference/ds:DigestValue", NS).content = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(self.class.send(:canonicalize, target)))
      info = signature.at_xpath("ds:SignedInfo", NS)
      signature.at_xpath("ds:SignatureValue", NS).content = Base64.strict_encode64(@certificado.key.sign(OpenSSL::Digest.new("SHA256"), self.class.send(:canonicalize, info)))
      doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
    end

    # Integrity self-test with the embedded certificate; does not establish ICP-Brasil trust.
    def self.verify!(xml, node:)
      _doc, target = document_and_target(xml, node)
      signatures = target.parent.xpath("ds:Signature", NS)
      raise Invalid, "Assinatura ausente ou duplicada" unless signatures.size == 1
      signature = signatures.first
      infos = signature.xpath("ds:SignedInfo", NS)
      raise Invalid, "SignedInfo ausente ou duplicado" unless infos.size == 1
      info = infos.first
      references = info.xpath("ds:Reference", NS)
      raise Invalid, "Referência de assinatura inválida" unless references.size == 1 && references.first["URI"] == "##{target["Id"]}"
      reference = references.first
      unless info.xpath("ds:CanonicalizationMethod/@Algorithm", NS).map(&:value) == [ALGORITHMS[:canonicalization]] &&
          info.xpath("ds:SignatureMethod/@Algorithm", NS).map(&:value) == [ALGORITHMS[:signature]] &&
          reference.xpath("ds:DigestMethod/@Algorithm", NS).map(&:value) == [ALGORITHMS[:digest]] &&
          reference.xpath("ds:Transforms/ds:Transform/@Algorithm", NS).map(&:value) == [ALGORITHMS[:enveloped_transform], ALGORITHMS[:canonicalization]]
        raise Invalid, "Perfil de assinatura XML não suportado"
      end
      digest = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(canonicalize(target)))
      raise Invalid, "Digest da assinatura inválido" unless value(reference, "ds:DigestValue") == digest
      certificate = OpenSSL::X509::Certificate.new(decode(value(signature, "ds:KeyInfo/ds:X509Data/ds:X509Certificate")))
      valid = certificate.public_key.is_a?(OpenSSL::PKey::RSA) && certificate.public_key.verify(
        OpenSSL::Digest.new("SHA256"), decode(value(signature, "ds:SignatureValue")), canonicalize(info)
      )
      raise Invalid, "Assinatura XML inválida" unless valid
      true
    rescue OpenSSL::OpenSSLError, ArgumentError
      raise Invalid, "Certificado ou assinatura XML inválidos"
    end

    def self.document_and_target(xml, node)
      raise Invalid, "Nó de assinatura não suportado" unless %w[infDPS infPedReg].include?(node)
      doc = Nokogiri::XML(xml) {|config| config.strict.nonet}
      targets = doc.xpath("//*[local-name()='#{node}']")
      raise Invalid, "#{node} ausente ou duplicado" unless targets.size == 1
      target = targets.first
      id = target["Id"]
      raise Invalid, "#{node} sem atributo Id" if id.nil? || id.strip.empty?
      ids = doc.xpath("//*[@Id]").count {|element| element["Id"] == id}
      raise Invalid, "Id de assinatura duplicado" unless ids == 1
      raise Invalid, "Nó de assinatura fora da raiz" unless target.parent == doc.root
      [doc, target]
    rescue Nokogiri::XML::SyntaxError
      raise Invalid, "XML inválido para assinatura"
    end

    def self.canonicalize(node)
      node.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, nil, true)
    end

    def self.value(node, path)
      elements = node.xpath(path, NS)
      raise Invalid, "Campo de assinatura ausente ou duplicado" unless elements.size == 1
      elements.first.text
    end

    def self.decode(text)
      Base64.strict_decode64(text.gsub(/\s+/, ""))
    end

    private_class_method :document_and_target, :canonicalize, :value, :decode
  end
end
