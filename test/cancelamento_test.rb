require_relative "test_helper"

class NfseNacionalCancelamentoTest < NfseNacional::TestCase
  KEY = "1" * 50
  NS = {"n" => "http://www.sped.fazenda.gov.br/nfse"}.freeze

  test "pedido segue o XSD oficial sem sequência no Id nem tag nPedRegEvento" do
    xml = cancellation.to_xml
    assert_nothing_raised { NfseNacional::Schema.validate_cancelamento!(xml) }
    doc = Nokogiri::XML(xml)
    assert_equal "1.00", doc.root["versao"]
    assert_equal "PRE#{KEY}101101", doc.at_xpath("//n:infPedReg", NS)["Id"]
    assert_equal %w[tpAmb verAplic dhEvento CNPJAutor chNFSe e101101], doc.at_xpath("//n:infPedReg", NS).element_children.map(&:name)
    assert_equal "2", doc.at_xpath("//n:tpAmb", NS).text
    assert_equal "OutroApp-1", doc.at_xpath("//n:verAplic", NS).text
    assert_equal "2026-10-16T12:29:55-03:00", doc.at_xpath("//n:dhEvento", NS).text
    assert_equal "12345678000195", doc.at_xpath("//n:CNPJAutor", NS).text
    assert_equal KEY, doc.at_xpath("//n:chNFSe", NS).text
    assert_equal "Cancelamento de NFS-e", doc.at_xpath("//n:xDesc", NS).text
    assert_equal "1", doc.at_xpath("//n:cMotivo", NS).text
    assert_equal "Erro na emissão & conferência", doc.at_xpath("//n:xMotivo", NS).text
  end

  test "produção e outros motivos previstos no schema" do
    %w[2 9].each do |code|
      xml = cancellation(ambiente: :producao, codigo_motivo: code).to_xml
      NfseNacional::Schema.validate_cancelamento!(xml)
      assert_equal "1", Nokogiri::XML(xml).at_xpath("//n:tpAmb", NS).text
    end
  end

  test "XSD rejeita chave CNPJ motivo código e estrutura inválidos" do
    [{access_key: "123"}, {cnpj_autor: "123"}, {motivo: "curto"}, {codigo_motivo: "3"}].each do |attributes|
      assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_cancelamento!(cancellation(**attributes).to_xml) }
    end
    assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_cancelamento!("<pedRegEvento>") }
  end

  test "recusa sequência não suportada pelo leiaute do pedido" do
    assert_raises(ArgumentError) { cancellation(numero_pedido: 2) }
  end

  test "ver_aplic: padrão, nome do app e limite de 20" do
    base = {access_key: "1" * 50, ambiente: :homologacao, cnpj_autor: "12345678000195", motivo: "Erro na emissão da nota de teste"}
    padrao = NfseNacional::Cancelamento.new(**base).to_xml
    NfseNacional::Schema.validate_cancelamento!(padrao)
    assert_includes padrao, "<verAplic>nfse_nacional</verAplic>"
    assert_includes NfseNacional::Cancelamento.new(**base, ver_aplic: "OutroApp-1").to_xml, "<verAplic>OutroApp-1</verAplic>"
    assert_raises(ArgumentError) { NfseNacional::Cancelamento.new(**base, ver_aplic: "x" * 21) }
    assert_raises(ArgumentError) { NfseNacional::Client.new(certificado: nil, ver_aplic: "x" * 21) }
  end

  test "CNPJ do autor é normalizado como os demais documentos" do
    assert_equal "12345678000195", Nokogiri::XML(cancellation(cnpj_autor: "12.345.678/0001-95").to_xml).at_xpath("//n:CNPJAutor", NS).text
  end

  test "CNPJ alfanumérico do autor é recusado: o XSD de eventos 1.00 só aceita números" do
    error = assert_raises(ArgumentError) { cancellation(cnpj_autor: "12.abc.345/01de-35") }
    assert_equal "Cancelamento com CNPJ alfanumérico ainda não é aceito: o XSD de eventos 1.00 só admite números", error.message
  end

  private

  def cancellation(**attributes)
    NfseNacional::Cancelamento.new(access_key: KEY, ambiente: :homologacao, cnpj_autor: "12.345.678/0001-95",
      motivo: "Erro na emissão & conferência", ver_aplic: "OutroApp-1", now: Time.new(2026, 10, 16, 12, 30, 0, "-03:00"), **attributes)
  end
end
