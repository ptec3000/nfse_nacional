require "bigdecimal"
require_relative "test_helper"

class NfseNacionalDpsNationalTomadorAddressTest < NfseNacional::TestCase
  NS = {"n" => "http://www.sped.fazenda.gov.br/nfse"}.freeze
  ENDERECO = {municipio_ibge: "3106200", cep: "30.130-010", logradouro: "Avenida Afonso Pena",
              numero: "1500", complemento: "Sala 2", bairro: "Centro"}.freeze

  setup do
    @attributes = {
      ambiente: :homologacao,
      prestador: {cnpj: "12345678000195", im: "123", nome: "Empresa Exemplo Ltda", municipio_ibge: "3106200",
                  op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
      tomador: {documento: "12345678909", nome: "Cliente", email: "c@example.test"},
      servico: {c_trib_nac: "010501", c_trib_mun: "001", nbs: "111032200",
                descricao: "Sessão de outubro", municipio_prestacao_ibge: "3106200"},
      valores: {valor: BigDecimal("199.90"), trib_issqn: "1", tp_ret_issqn: "1", pis_cofins: nil, p_tot_trib_sn: "6.00"},
      competencia: Date.new(2026, 10, 1), serie: "900", numero: "1", ver_aplic: "NotaApp-1",
      now: Time.new(2026, 10, 16, 12, 30, 0, "-03:00")
    }
  end

  test "tomador com CPF e endereço completo leva end/endNac na ordem do XSD e valida nos dois leiautes" do
    dps = dps_with(ENDERECO)

    [:atual, :rtc].each do |leiaute|
      xml = dps.to_xml(leiaute: leiaute)
      NfseNacional::Schema.validate_dps!(xml, leiaute: leiaute)

      toma = Nokogiri::XML(xml).at_xpath("//n:toma", NS)
      assert_equal %w[CPF xNome end email], toma.element_children.map(&:name)
      address = toma.at_xpath("n:end", NS)
      assert_equal %w[endNac xLgr nro xCpl xBairro], address.element_children.map(&:name)
      assert_equal "3106200", address.at_xpath("n:endNac/n:cMun", NS).text
      assert_equal "30130010", address.at_xpath("n:endNac/n:CEP", NS).text
      assert_equal "Avenida Afonso Pena", address.at_xpath("n:xLgr", NS).text
      assert_equal "1500", address.at_xpath("n:nro", NS).text
      assert_equal "Sala 2", address.at_xpath("n:xCpl", NS).text
      assert_equal "Centro", address.at_xpath("n:xBairro", NS).text
    end
  end

  test "tomador com CNPJ e endereço sem complemento sai sem xCpl" do
    dps = dps_with(ENDERECO.merge(complemento: " "), documento: "12345678000195", nome: "Loja PJ")
    xml = dps.to_xml
    NfseNacional::Schema.validate_dps!(xml)

    address = Nokogiri::XML(xml).at_xpath("//n:toma/n:end", NS)
    assert_equal %w[endNac xLgr nro xBairro], address.element_children.map(&:name)
  end

  test "espaços sobrando são tirados para o XML passar no padrão do XSD" do
    dps = dps_with(ENDERECO.merge(logradouro: "  Rua  das\nFlores ", numero: " S/N ", bairro: " Centro "))
    xml = dps.to_xml(leiaute: :rtc)
    NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)

    address = Nokogiri::XML(xml).at_xpath("//n:toma/n:end", NS)
    assert_equal "Rua das Flores", address.at_xpath("n:xLgr", NS).text
    assert_equal "S/N", address.at_xpath("n:nro", NS).text
    assert_equal "Centro", address.at_xpath("n:xBairro", NS).text
  end

  test "sem endereço, ou com endereço incompleto, a DPS sai igual à de hoje nos dois leiautes" do
    [:atual, :rtc].each do |leiaute|
      baseline = NfseNacional::Dps.new(**@attributes).to_xml(leiaute: leiaute)

      [nil, {}, ENDERECO.merge(bairro: ""), ENDERECO.except(:cep), ENDERECO.merge(municipio_ibge: nil),
        ENDERECO.merge(logradouro: "  "), ENDERECO.merge(bairro: "\u00A0"), ENDERECO.except(:numero)].each do |endereco|
        tomador = @attributes[:tomador].merge(endereco: endereco)
        assert_equal baseline, NfseNacional::Dps.new(**@attributes.merge(tomador: tomador)).to_xml(leiaute: leiaute),
          "endereço #{endereco.inspect} deveria ser ignorado no #{leiaute}"
      end
    end
  end

  test "endereço com chaves em string também vai" do
    xml = dps_with(ENDERECO.transform_keys(&:to_s)).to_xml(leiaute: :rtc)
    assert_equal "30130010", Nokogiri::XML(xml).at_xpath("//n:toma/n:end/n:endNac/n:CEP", NS).text
  end

  test "aspas e travessões do celular viram os simples e o XML valida" do
    xml = dps_with(ENDERECO.merge(logradouro: "Rua D’Ávila – Q. 3", complemento: "“Fundos”")).to_xml(leiaute: :rtc)
    NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)

    address = Nokogiri::XML(xml).at_xpath("//n:toma/n:end", NS)
    assert_equal "Rua D'Ávila - Q. 3", address.at_xpath("n:xLgr", NS).text
    assert_equal '"Fundos"', address.at_xpath("n:xCpl", NS).text
  end

  test "endereço completo com valor fora do formato do XSD é recusado com mensagem clara" do
    {
      {cep: "3013001"} => /CEP do tomador/,
      {municipio_ibge: "310620"} => /município do tomador/,
      {logradouro: "a" * 256} => /logradouro do tomador.*255/,
      {numero: "1" * 61} => /número do tomador.*60/,
      {complemento: "c" * 157} => /complemento do tomador.*156/,
      {bairro: "b" * 61} => /bairro do tomador.*60/,
      {logradouro: "Rua ☆ Estrela"} => /logradouro do tomador tem caractere não aceito pela Sefin/
    }.each do |change, message|
      error = assert_raises(ArgumentError, change.inspect) { dps_with(ENDERECO.merge(change)) }
      assert_match message, error.message
    end
  end

  test "endereço nos limites do XSD é aceito" do
    dps = dps_with(ENDERECO.merge(logradouro: "a" * 255, numero: "1" * 60, complemento: "c" * 156, bairro: "b" * 60))
    NfseNacional::Schema.validate_dps!(dps.to_xml(leiaute: :rtc), leiaute: :rtc)
  end

  test "tomador estrangeiro continua com endExt" do
    tomador = {nome: "Client", nif: "123", endereco: {pais: "US", codigo_postal: "10001", cidade: "New York",
                                                      estado: "NY", logradouro: "5th Ave", numero: "1", bairro: "Manhattan"}}
    xml = NfseNacional::Dps.new(**@attributes.merge(tomador: tomador)).to_xml(leiaute: :rtc)

    assert Nokogiri::XML(xml).at_xpath("//n:toma/n:end/n:endExt", NS)
    assert_nil Nokogiri::XML(xml).at_xpath("//n:toma/n:end/n:endNac", NS)
  end

  private

  def dps_with(endereco, **tomador)
    NfseNacional::Dps.new(**@attributes.merge(tomador: @attributes[:tomador].merge(tomador, endereco: endereco)))
  end
end
