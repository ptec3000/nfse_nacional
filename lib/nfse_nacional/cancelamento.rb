require "nokogiri"

module NfseNacional
  class Cancelamento
    def initialize(access_key:, ambiente:, cnpj_autor:, motivo:, codigo_motivo: "1", numero_pedido: 1,
      ver_aplic: NfseNacional::VER_APLIC, now: Time.now)
      # O leiaute 1.00 não admite sequência em infPedReg (TSIdPedRefEvt).
      raise ArgumentError, "Leiaute 1.00 suporta apenas numero_pedido 1" unless numero_pedido.to_s == "1"
      @access_key = access_key
      @ambiente = AMBIENTES.fetch(ambiente)
      @cnpj_autor = cnpj_autor.to_s.gsub(/\D/, "")
      @motivo = motivo
      @codigo_motivo = codigo_motivo
      @ver_aplic = NfseNacional.ver_aplic!(ver_aplic)
      @now = now
    end

    def to_xml
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.pedRegEvento("xmlns" => "http://www.sped.fazenda.gov.br/nfse", "versao" => "1.00") do
          xml.infPedReg("Id" => "PRE#{@access_key}101101") do
            xml.tpAmb @ambiente
            xml.verAplic @ver_aplic
            xml.dhEvento (@now - DHEMI_SAFETY_SECONDS).strftime("%Y-%m-%dT%H:%M:%S%:z")
            xml.CNPJAutor @cnpj_autor
            xml.chNFSe @access_key
            xml.e101101 do
              xml.xDesc "Cancelamento de NFS-e"
              xml.cMotivo @codigo_motivo
              xml.xMotivo @motivo
            end
          end
        end
      end.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
    end
  end
end
