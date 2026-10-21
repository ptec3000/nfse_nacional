require_relative "test_helper"

class NfseNacionalSignerTest < NfseNacional::TestCase
  NS = {"n" => "http://www.sped.fazenda.gov.br/nfse", "ds" => "http://www.w3.org/2000/09/xmldsig#"}.freeze

  setup do
    @cert = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx, senha: "teste")
    @signer = NfseNacional::Signer.new(@cert)
    @xml = File.read(fixture_path("dps_golden.xml"))
  end

  test "assina DPS com perfil e posição do template xmlsec de produção" do
    signed = @signer.sign(@xml, node: "infDPS")
    assert NfseNacional::Signer.verify!(signed, node: "infDPS")
    doc = Nokogiri::XML(signed)
    assert_equal ["infDPS", "Signature"], doc.root.element_children.map(&:name)
    assert_equal @cert.certificate.to_der, Base64.decode64(doc.at_xpath("//ds:X509Certificate", NS).text)
  end

  test "DPS sem assinatura valida no XSD" do
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(@xml) }
  end

  test "DPS assinada passa em Signer.verify!" do
    signed = @signer.sign(@xml, node: "infDPS")
    assert NfseNacional::Signer.verify!(signed, node: "infDPS")
  end

  test "assinatura usa exatamente os URIs do perfil aceito pela Sefin em produção" do
    expected_algorithms = {
      canonicalization: "http://www.w3.org/2001/10/xml-exc-c14n#WithComments",
      signature: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
      enveloped_transform: "http://www.w3.org/2000/09/xmldsig#enveloped-signature",
      digest: "http://www.w3.org/2001/04/xmlenc#sha256"
    }
    signed = @signer.sign(@xml, node: "infDPS")
    doc = Nokogiri::XML(signed)
    info = doc.at_xpath("/n:DPS/ds:Signature/ds:SignedInfo", NS)
    reference = info.at_xpath("ds:Reference", NS)
    transforms = reference.xpath("ds:Transforms/ds:Transform", NS).map { |transform| transform["Algorithm"] }

    actual_algorithms = {
      canonicalization: info.at_xpath("ds:CanonicalizationMethod", NS)["Algorithm"],
      signature: info.at_xpath("ds:SignatureMethod", NS)["Algorithm"],
      enveloped_transform: transforms.first,
      digest: reference.at_xpath("ds:DigestMethod", NS)["Algorithm"]
    }

    assert_equal expected_algorithms, actual_algorithms
    assert_equal [expected_algorithms[:enveloped_transform], expected_algorithms[:canonicalization]], transforms
    flunk "Signer deve centralizar o perfil em ALGORITHMS" unless NfseNacional::Signer.const_defined?(:ALGORITHMS, false)
    assert_equal expected_algorithms, NfseNacional::Signer::ALGORITHMS
  end

  test "assinatura confere independentemente com OpenSSL e o digest da infDPS" do
    signed = @signer.sign(@xml, node: "infDPS")
    doc = Nokogiri::XML(signed)
    info = doc.at_xpath("/n:DPS/ds:Signature/ds:SignedInfo", NS)
    reference = info.at_xpath("ds:Reference", NS)
    # Independent OpenSSL check catches signer/verifier sharing the same canonicalization bug.
    assert @cert.certificate.public_key.verify(OpenSSL::Digest.new("SHA256"),
      Base64.decode64(doc.at_xpath("//ds:SignatureValue", NS).text),
      info.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, nil, true))
    assert_equal Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(doc.at_xpath("/n:DPS/n:infDPS", NS).canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, nil, true))), reference.at_xpath("ds:DigestValue", NS).text
  end

  test "alteração do conteúdo ou assinatura é rejeitada" do
    signed = @signer.sign(@xml, node: "infDPS")
    altered = signed.sub("199.90", "299.90")
    assert_not_equal signed, altered
    assert_raises(NfseNacional::Signer::Invalid) { NfseNacional::Signer.verify!(altered, node: "infDPS") }
    doc = Nokogiri::XML(signed)
    doc.at_xpath("//ds:SignatureValue", NS).content = Base64.strict_encode64("invalid")
    assert_raises(NfseNacional::Signer::Invalid) { NfseNacional::Signer.verify!(doc.to_xml, node: "infDPS") }
  end

  test "assina infPedReg e substitui assinatura anterior" do
    xml = '<pedRegEvento xmlns="http://www.sped.fazenda.gov.br/nfse"><infPedReg Id="PRE123"><xMotivo>Teste</xMotivo></infPedReg></pedRegEvento>'
    signed = @signer.sign(@signer.sign(xml, node: "infPedReg"), node: "infPedReg")
    assert_equal 1, Nokogiri::XML(signed).xpath("//ds:Signature", NS).size
    assert NfseNacional::Signer.verify!(signed, node: "infPedReg")
  end

  test "preserva espaços e inclui comentários na assinatura" do
    xml = '<pedRegEvento xmlns="http://www.sped.fazenda.gov.br/nfse">
  <infPedReg Id="PRE123"><!-- comentário assinado --><xMotivo>  Motivo com espaços  </xMotivo></infPedReg>
</pedRegEvento>'
    signed = @signer.sign(xml, node: "infPedReg")
    assert NfseNacional::Signer.verify!(signed, node: "infPedReg")
    assert_equal "  Motivo com espaços  ", Nokogiri::XML(signed).at_xpath("//n:xMotivo", NS).text
    assert_raises(NfseNacional::Signer::Invalid) do
      NfseNacional::Signer.verify!(signed.sub("comentário assinado", "comentário alterado"), node: "infPedReg")
    end
  end

  test "recusa XML malformado nó ausente Id ausente e Id duplicado" do
    ["<DPS>", "<DPS/>", "<DPS><infDPS/></DPS>", '<DPS><infDPS Id="x"/><outro Id="x"/></DPS>'].each do |xml|
      assert_raises(NfseNacional::Signer::Invalid) { @signer.sign(xml, node: "infDPS") }
    end
    assert_raises(NfseNacional::Signer::Invalid) { NfseNacional::Signer.verify!(@xml, node: "infDPS") }
  end

  test "recusa referência desviada perfil alterado e nó duplicado" do
    signed = @signer.sign(@xml, node: "infDPS")
    [->(doc) { doc.at_xpath("//ds:Reference", NS)["URI"] = "#outro" },
      ->(doc) { doc.at_xpath("//ds:DigestMethod", NS)["Algorithm"] = "sha1" },
      ->(doc) { doc.root.add_child(doc.at_xpath("//n:infDPS", NS).dup) }].each do |mutate|
      doc = Nokogiri::XML(signed)
      mutate.call(doc)
      assert_raises(NfseNacional::Signer::Invalid) { NfseNacional::Signer.verify!(doc.to_xml, node: "infDPS") }
    end
  end
end
