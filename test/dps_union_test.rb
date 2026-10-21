require_relative "test_helper"

class NfseNacionalDpsUnionTest < NfseNacional::TestCase
  NS = {"n" => "http://www.sped.fazenda.gov.br/nfse"}.freeze

  def attributes(**overrides)
    {
      ambiente: :homologacao,
      prestador: {cnpj: "12345678000195", municipio_ibge: "3106200", op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
      tomador: {documento: "12345678909", nome: "Cliente Exemplo", email: "cliente@example.com"},
      servico: {c_trib_nac: "010501", municipio_prestacao_ibge: "3106200", descricao: "Serviço de exemplo", nbs: "111032200"},
      valores: {valor: "100.00", trib_issqn: "1", tp_ret_issqn: "1", pis_cofins: nil},
      competencia: Date.new(2026, 10, 20), serie: "900", numero: "1",
      now: Time.new(2026, 10, 20, 12, 0, 0, "-03:00")
    }.merge(overrides)
  end

  IBS_CBS = {c_ind_op: "030101", cst: "000", c_class_trib: "000001"}.freeze

  def dps(valores = {}, **overrides)
    NfseNacional::Dps.new(**attributes(valores: attributes[:valores].merge(valores), ibs_cbs: IBS_CBS, **overrides))
  end

  # Gera nos dois leiautes, valida cada um no XSD e devolve o totTrib do leiaute pedido.
  def tot_trib(valores, leiaute: :atual)
    nodes = %i[atual rtc].to_h do |each_leiaute|
      xml = dps(valores).to_xml(leiaute: each_leiaute)
      NfseNacional::Schema.validate_dps!(xml, leiaute: each_leiaute)
      [each_leiaute, Nokogiri::XML(xml).at_xpath("//n:totTrib", NS)]
    end
    nodes.fetch(leiaute)
  end

  test "ver_aplic padrão é nfse_nacional" do
    xml = dps.to_xml
    NfseNacional::Schema.validate_dps!(xml, leiaute: :atual)
    assert_includes xml, "<verAplic>nfse_nacional</verAplic>"
  end

  test "ver_aplic do app vai no XML" do
    xml = dps(ver_aplic: "NotaApp-1").to_xml
    NfseNacional::Schema.validate_dps!(xml, leiaute: :atual)
    assert_includes xml, "<verAplic>NotaApp-1</verAplic>"
  end

  test "ver_aplic com mais de 20 caracteres é recusado" do
    assert_raises(ArgumentError) { dps(ver_aplic: "x" * 21) }
    assert dps(ver_aplic: "x" * 20)
  end

  test "totTrib: percentuais vencem tot_trib" do
    node = tot_trib({tot_trib_percentual: {fed: "1.00", est: "2.00", mun: "3.00"}, tot_trib: {ind_tot_trib: "0"}})
    assert node.at_xpath("n:pTotTrib", NS)
    assert_nil node.at_xpath("n:indTotTrib", NS)
  end

  test "totTrib: ind_tot_trib por presença da chave" do
    node = tot_trib({tot_trib: {ind_tot_trib: "0"}})
    assert_equal "0", node.at_xpath("n:indTotTrib", NS).text
  end

  test "totTrib: tot_trib com p_tot_trib_sn" do
    node = tot_trib({tot_trib: {p_tot_trib_sn: "4.50"}})
    assert_equal "4.50", node.at_xpath("n:pTotTribSN", NS).text
  end

  test "totTrib: tot_trib vazio não cai no padrão 6.00" do
    vazio = dps({tot_trib: {}})
    assert_raises(ArgumentError) { vazio.to_xml }
  end

  test "totTrib: sem tot_trib usa p_tot_trib_sn ou 6.00" do
    assert_equal "6.00", tot_trib({}).at_xpath("n:pTotTribSN", NS).text
    assert_equal "5.00", tot_trib({p_tot_trib_sn: "5.00"}).at_xpath("n:pTotTribSN", NS).text
    assert_equal "6.00", tot_trib({tot_trib: nil}).at_xpath("n:pTotTribSN", NS).text
  end

  test "e-mail do tomador vazio ou só espaços é omitido e a DPS continua válida" do
    ["", "   "].each do |email|
      xml = dps(tomador: attributes[:tomador].merge(email: email)).to_xml
      NfseNacional::Schema.validate_dps!(xml, leiaute: :atual)
      refute_includes xml, "<email"
    end
  end

  test "pis_cofins continua obrigatório como chave" do
    sem_chave = NfseNacional::Dps.new(**attributes(valores: attributes[:valores].except(:pis_cofins)))
    assert_raises(KeyError) { sem_chave.to_xml }
  end
end
