require "bigdecimal"
require_relative "test_helper"

class NfseNacionalDpsExportTest < NfseNacional::TestCase
  def export_attributes
    {
      ambiente: :homologacao,
      prestador: {cnpj: "44390365000145", nome: "Empresa Exemplo Ltda", municipio_ibge: "4321501",
                  op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
      tomador: {nome: "Wavelo, Inc.", email: nil, nif: nil, nao_nif: "2",
                endereco: {pais: "US", codigo_postal: "39759", cidade: "Starkville", estado: "MS",
                           logradouro: "DR. MARTIN LUTHER KING JR. DRIVE EAST", numero: "421", complemento: nil,
                           bairro: "MASSACHUSETTS"}},
      servico: {c_trib_nac: "010701", nbs: "115013000", descricao: "Configuração e manutenção de programas de computação .",
                pais_prestacao: "US",
                comercio_exterior: {modo_prestacao: "1", vinculo: "0", moeda: "220", valor_moeda: BigDecimal("3700.00"),
                                    mec_prestador: "01", mec_tomador: "01", mov_temp_bens: "1", mdic: "0"}},
      valores: {valor: BigDecimal("20518.65"), trib_issqn: "3", tp_ret_issqn: "1",
                pis_cofins: nil, tot_trib_percentual: {fed: "13.45", est: "0", mun: "2.00"}},
      competencia: Date.new(2026, 6, 9), serie: "900", numero: "1",
      now: Time.new(2026, 7, 8, 17, 41, 10, "-03:00")
    }
  end

  def xml
    Nokogiri::XML(NfseNacional::Dps.new(**export_attributes).to_xml).tap(&:remove_namespaces!)
  end

  test "exportação no leiaute rtc valida no XSD derivado" do
    xml = NfseNacional::Dps.new(**export_attributes, ibs_cbs: {c_ind_op: "030101", cst: "000", c_class_trib: "000001"})
      .to_xml(leiaute: :rtc)
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc) }
  end

  test "DPS de exportação valida no XSD" do
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(NfseNacional::Dps.new(**export_attributes).to_xml) }
  end

  test "tomador estrangeiro sem NIF vai com cNaoNIF e endereço no exterior" do
    toma = xml.at("infDPS/toma")
    assert_equal "2", toma.at("cNaoNIF").text
    assert_nil toma.at("CNPJ")
    assert_equal "Wavelo, Inc.", toma.at("xNome").text
    assert_equal "US", toma.at("end/endExt/cPais").text
    assert_equal "39759", toma.at("end/endExt/cEndPost").text
    assert_equal "Starkville", toma.at("end/endExt/xCidade").text
    assert_equal "MS", toma.at("end/endExt/xEstProvReg").text
    assert_equal "421", toma.at("end/nro").text
  end

  test "tomador estrangeiro com NIF usa NIF" do
    attrs = export_attributes
    attrs[:tomador][:nif] = "12-3456789"
    toma = Nokogiri::XML(NfseNacional::Dps.new(**attrs).to_xml).tap(&:remove_namespaces!).at("infDPS/toma")
    assert_equal "12-3456789", toma.at("NIF").text
    assert_nil toma.at("cNaoNIF")
  end

  test "exportação: país da prestação, comExt, tribISSQN 3 sem país do resultado, sem PIS/COFINS, pTotTrib" do
    doc = xml
    assert_equal "US", doc.at("serv/locPrest/cPaisPrestacao").text
    assert_nil doc.at("serv/locPrest/cLocPrestacao")
    ext = doc.at("serv/comExt")
    assert_equal %w[1 0 220 3700.00 01 01 1 0], %w[mdPrestacao vincPrest tpMoeda vServMoeda mecAFComexP mecAFComexT movTempBens mdic].map { |n| ext.at(n).text }
    assert_equal "3", doc.at("valores/trib/tribMun/tribISSQN").text
    assert_nil doc.at("valores/trib/tribMun/cPaisResult")
    assert_nil doc.at("valores/trib/tribFed")
    assert_equal %w[13.45 0.00 2.00], %w[pTotTribFed pTotTribEst pTotTribMun].map { |n| doc.at("valores/trib/totTrib/pTotTrib/#{n}").text }
    assert_nil doc.at("valores/trib/totTrib/pTotTribSN")
  end

  test "chave pis_cofins ausente gera KeyError para tomador nacional" do
    attributes = export_attributes.merge(
      tomador: {documento: "12345678909", nome: "Loja X"},
      servico: {c_trib_nac: "010701", municipio_prestacao_ibge: "4321501", descricao: "Serviço"},
      valores: {valor: BigDecimal("10.00"), trib_issqn: "1", tp_ret_issqn: "1"}
    )

    assert_raises(KeyError) { NfseNacional::Dps.new(**attributes).to_xml }
  end
end
