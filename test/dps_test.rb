require "bigdecimal"
require_relative "test_helper"

class NfseNacionalDpsTest < NfseNacional::TestCase
  RENTAL_SERVICO = {c_trib_nac: "990101", nbs: "111024000", municipio_prestacao_ibge: "5300108",
                    descricao: "Locação de equipamento (7 dias)"}.freeze

  RENTAL_GOLDEN_ATTRIBUTES = {
    ambiente: :homologacao,
    prestador: {cnpj: "11222333000181", im: nil, nome: "Empresa Exemplo Ltda", municipio_ibge: "5300108", op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
    tomador: {documento: "12345678909", nome: "Cliente", email: "c@example.test"},
    servico: {c_trib_nac: "990101", nbs: "111024000", municipio_prestacao_ibge: "5300108", descricao: "Locação de equipamento (7 dias)"},
    valores: {valor: BigDecimal("45.00"), trib_issqn: "4", tp_ret_issqn: "1", pis_cofins: nil, tot_trib: {p_tot_trib_sn: "4.00"}},
    ver_aplic: "NotaApp-1", competencia: Date.new(2026, 10, 1), serie: "900", numero: "42", now: Time.new(2026, 10, 16, 12, 30, 0, "-03:00")
  }.freeze

  IBS_CBS = {c_ind_op: "030101", cst: "000", c_class_trib: "000001"}.freeze

  setup do
    @attributes = {
      ambiente: :homologacao,
      prestador: {cnpj: "12345678000195", im: "123", nome: "Empresa Exemplo Ltda", municipio_ibge: "3106200",
                  op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
      tomador: {documento: "12345678909", nome: "Loja X", email: "x@y.com"},
      servico: {c_trib_nac: "010501", c_trib_mun: "001", nbs: "111032200",
                descricao: "Mensalidade de setembro de 2026",
                municipio_prestacao_ibge: "3106200"},
      valores: {valor: BigDecimal("199.90"), trib_issqn: "1", tp_ret_issqn: "1",
                pis_cofins: {cst: "01", base: nil, aliq_pis: "0.65", aliq_cofins: "3.00", tp_ret: "2"},
                p_tot_trib_sn: "6.00"},
      competencia: Date.new(2026, 10, 1), serie: "900", numero: "123456789012",
      versao: "1.00", ver_aplic: "NotaApp-1", tp_emit: "1", now: Time.new(2026, 10, 16, 12, 30, 0, "-03:00")
    }
  end

  test "verAplic padrão identifica a aplicação" do
    xml = NfseNacional::Dps.new(**@attributes.except(:ver_aplic)).to_xml
    assert_equal NfseNacional::VER_APLIC, document(xml).at_xpath("//n:verAplic", namespaces).text
  end

  test "tomador brasileiro sem e-mail sai sem <email> e valida no XSD" do
    xml = dps(tomador: @attributes[:tomador].merge(email: "")).to_xml
    NfseNacional::Schema.validate_dps!(xml)
    assert_nil document(xml).at_xpath("//n:toma/n:email", namespaces)
  end

  test "id usa município tipo inscrição documento série e número com padding do script" do
    assert_equal "DPS310620021234567800019500900000123456789012", dps.id
  end

  test "XML válido no XSD com CPF CNPJ e sem tomador" do
    [@attributes[:tomador], {documento: "12345678000195", nome: "Loja PJ"}, nil].each do |recipient|
      xml = dps(tomador: recipient).to_xml
      NfseNacional::Schema.validate_dps!(xml)
      assert_equal Encoding::UTF_8, xml.encoding
      if recipient
        tag = (recipient[:documento].length == 11) ? "CPF" : "CNPJ"
        assert_equal recipient[:documento], document(xml).at_xpath("//n:toma/n:#{tag}", namespaces).text
      else
        assert_nil document(xml).at_xpath("//n:toma", namespaces)
      end
    end
  end

  test "documento vazio descarta nome e email do tomador" do
    [nil, "", "   ", " .-/ "].each do |value|
      xml = dps(tomador: {documento: value, nome: "Loja X", email: "x@y.com"}).to_xml
      assert_nil document(xml).at_xpath("//n:toma", namespaces)
    end
  end

  test "documento exige nome do tomador" do
    [nil, "", "   "].each do |name|
      error = assert_raises(ArgumentError) {dps(tomador: {documento: "12345678909", nome: name}).to_xml}
      assert_equal "Tomador incompleto: informe o nome quando houver CPF/CNPJ", error.message
    end
  end

  test "dhEmi recua cinco segundos preservando o offset" do
    assert_equal "2026-10-16T12:29:55-03:00", text("dhEmi")
  end

  test "PIS e COFINS calculados com base padrão e base explícita" do
    assert_equal "1.30", text("vPis")
    assert_equal "6.00", text("vCofins")
    @attributes[:valores][:pis_cofins][:base] = BigDecimal("100.01")
    assert_equal "100.01", text("vBCPisCofins")
    assert_equal "0.65", text("vPis")
    assert_equal "3.00", text("vCofins")
  end

  test "valores e alíquotas usam duas casas e arredondamento do script" do
    @attributes[:valores][:valor] = BigDecimal("199.905")
    @attributes[:valores][:pis_cofins][:aliq_pis] = "0.655"
    assert_equal "199.91", text("vServ")
    assert_equal "0.66", text("pAliqPis")
    assert_equal "1.32", text("vPis")
  end

  test "regApTribSN depende de opSimpNac igual a três" do
    assert_equal "1", text("regApTribSN")
    @attributes[:prestador][:op_simp_nac] = "1"
    assert_nil text("regApTribSN")
    NfseNacional::Schema.validate_dps!(dps.to_xml)
  end

  test "nome do prestador só aparece quando tpEmit difere de um" do
    assert_nil document(dps.to_xml).at_xpath("//n:prest/n:xNome", namespaces)
    assert_equal "Empresa Exemplo Ltda", document(dps(tp_emit: "2").to_xml).at_xpath("//n:prest/n:xNome", namespaces).text
  end

  test "cTribMun só aparece com três dígitos" do
    [nil, "12", "1234"].each do |code|
      @attributes[:servico][:c_trib_mun] = code
      assert_nil text("cTribMun")
    end
    @attributes[:servico][:c_trib_mun] = "0-01"
    assert_equal "001", text("cTribMun")
  end

  test "ambiente de produção e documento formatado" do
    @attributes[:prestador][:cnpj] = "12.345.678/0001-95"
    assert_equal "1", text("tpAmb", ambiente: :producao)
    assert_equal "12345678000195", text("CNPJ")
    assert_equal "DPS310620021234567800019500900000123456789012", dps.id
    @attributes[:prestador][:cnpj] = "12345678909"
    assert_equal "DPS310620010001234567890900900000123456789012", dps.id
  end

  test "paridade literal com o XML de referência" do
    # Golden de referência, com o instante de emissão fixado neste teste.
    expected = File.read(fixture_path("dps_golden.xml"), encoding: "UTF-8")
    assert_equal expected, dps.to_xml
  end

  test "golden de referência é aceito pelo schema publicado para o leiaute 1.00" do
    xml = File.read(fixture_path("dps_golden.xml"), encoding: "UTF-8")

    assert_nothing_raised {NfseNacional::Schema.validate_dps!(xml)}
  end

  test "schema expõe erros de validação e rejeita XML malformado" do
    [dps.to_xml.sub("<nDPS>123456789012</nDPS>", "<nDPS>0</nDPS>"), "<DPS>"].each do |xml|
      error = assert_raises(NfseNacional::Schema::Invalid) {NfseNacional::Schema.validate_dps!(xml)}
      assert_not_empty error.errors
      assert_includes error.message, error.errors.first.to_s
    end
  end

  test "rtc gera a ordem aceita pela homologação e passa no XSD derivado" do
    xml = dps(ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc)
    NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)
    doc = Nokogiri::XML(xml).remove_namespaces!
    assert_equal "1.01", doc.root["versao"]
    assert_equal %w[tpAmb dhEmi verAplic serie nDPS dCompet tpEmit finNFSe cLocEmi prest toma serv valores IBSCBS],
      doc.at("infDPS").element_children.map(&:name)
    assert_equal %w[cTribNac cTribMun cNBS xDescServ], doc.at("cServ").element_children.map(&:name)
    assert_equal "0", doc.at("infDPS > finNFSe").text
    assert_equal ["030101", "0", "000", "000001"], %w[cIndOp indDest CST cClassTrib].map {doc.at("IBSCBS #{it}").text}
  end

  test "rtc é igual ao atual fora de versão, finNFSe, IBSCBS e posição do cNBS" do
    atual = Nokogiri::XML(dps(ibs_cbs: IBS_CBS).to_xml)
    rtc = Nokogiri::XML(dps(ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc))
    rtc.root["versao"] = "1.00"
    rtc.xpath("//*[local-name()='finNFSe' or local-name()='IBSCBS']").each(&:remove)
    rtc.at_xpath("//*[local-name()='cServ']").add_child(rtc.at_xpath("//*[local-name()='cNBS']"))
    assert_equal atual.to_xml, rtc.to_xml
  end

  test "rtc sem IBS CBS completo levanta erro claro" do
    [nil, {}, IBS_CBS.merge(cst: ""), IBS_CBS.except(:c_class_trib)].each do |ibs_cbs|
      error = assert_raises(NfseNacional::IbsCbsNaoConfigurado) {dps(ibs_cbs: ibs_cbs).to_xml(leiaute: :rtc)}
      assert_equal "IBS/CBS não configurado", error.message
    end
    assert_nothing_raised {dps(ibs_cbs: nil).to_xml}
  end

  test "id não depende do leiaute nem do IBS CBS" do
    assert_equal dps.id, dps(ibs_cbs: IBS_CBS).id
  end

  test "leiaute desconhecido é erro de programação" do
    assert_raises(ArgumentError) {dps(ibs_cbs: IBS_CBS).to_xml(leiaute: :novo)}
  end

  test "paridade literal com o XML de referência (cópia alternativa)" do
    # Golden de referência, com o instante de emissão fixado neste teste.
    expected = File.read(fixture_path("dps_golden.xml"), encoding: "UTF-8")
    assert_equal expected, dps.to_xml
    assert_equal expected, dps.to_xml(leiaute: :atual)
  end

  test "locação do Simples: sem tribFed, com pTotTribSN" do
    xml = rental_dps(op_simp_nac: "3", tot_trib: {p_tot_trib_sn: "4.00"}).to_xml
    NfseNacional::Schema.validate_dps!(xml)
    doc = Nokogiri::XML(xml).remove_namespaces!
    assert_equal "990101", doc.at("cTribNac").text
    assert_equal "4", doc.at("tribISSQN").text
    assert_nil doc.at("tribFed")
    assert_equal "4.00", doc.at("pTotTribSN").text
  end

  test "locação do MEI: opSimpNac 2, sem regApTribSN" do
    xml = rental_dps(op_simp_nac: "2", tot_trib: {p_tot_trib_sn: "0.00"}).to_xml
    NfseNacional::Schema.validate_dps!(xml)
    doc = Nokogiri::XML(xml).remove_namespaces!
    assert_equal "2", doc.at("opSimpNac").text
    assert_nil doc.at("regApTribSN")
  end

  test "locação do regime normal: indTotTrib 0" do
    xml = rental_dps(op_simp_nac: "1", tot_trib: {ind_tot_trib: "0"}).to_xml
    NfseNacional::Schema.validate_dps!(xml)
    doc = Nokogiri::XML(xml).remove_namespaces!
    assert_equal "0", doc.at("indTotTrib").text
    assert_nil doc.at("pTotTribSN")
  end

  test "locação no leiaute atual fica byte a byte igual ao golden" do
    expected = File.read(fixture_path("dps_locacao_golden.xml"), encoding: "UTF-8")
    dps = NfseNacional::Dps.new(**RENTAL_GOLDEN_ATTRIBUTES)
    assert_equal expected, dps.to_xml
    assert_equal expected, dps.to_xml(leiaute: :atual)
  end

  test "rtc gera a ordem aceita pela homologação e passa no XSD derivado (cópia alternativa)" do
    xml = dps(ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc)
    NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)
    doc = Nokogiri::XML(xml).remove_namespaces!
    assert_equal "1.01", doc.root["versao"]
    names = doc.at("infDPS").element_children.map(&:name)
    assert_equal %w[tpAmb dhEmi verAplic serie nDPS dCompet tpEmit finNFSe cLocEmi prest toma serv valores IBSCBS], names
    assert_equal "0", doc.at("infDPS > finNFSe").text
    assert_equal %w[cIndOp indDest valores], doc.at("IBSCBS").element_children.map(&:name)
    assert_equal ["030101", "0", "000", "000001"], %w[cIndOp indDest CST cClassTrib].map {doc.at("IBSCBS #{it}").text}
    assert_equal %w[CST cClassTrib], doc.at("IBSCBS > valores > trib").element_children.map(&:name)
    assert_equal %w[cTribNac cTribMun cNBS xDescServ], doc.at("cServ").element_children.map(&:name)
  end

  test "cNBS fica antes de xDescServ só no rtc" do
    atual = Nokogiri::XML(dps(ibs_cbs: IBS_CBS).to_xml).remove_namespaces!
    assert_equal %w[cTribNac cTribMun xDescServ cNBS], atual.at("cServ").element_children.map(&:name)
  end

  test "rtc é igual ao atual fora de versão, finNFSe, IBSCBS e a posição do cNBS (cópia alternativa)" do
    atual = Nokogiri::XML(dps(ibs_cbs: IBS_CBS).to_xml)
    rtc = Nokogiri::XML(dps(ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc))
    rtc.root["versao"] = "1.00"
    rtc.xpath("//*[local-name()='finNFSe' or local-name()='IBSCBS']").each(&:remove)
    rtc_nbs = rtc.at_xpath("//*[local-name()='cNBS']")
    rtc.at_xpath("//*[local-name()='xDescServ']").add_next_sibling(rtc_nbs)
    assert_equal atual.to_xml, rtc.to_xml
  end

  test "rtc passa no XSD derivado sem tomador, com CNPJ e sem tribFed" do
    [nil, {documento: "12345678000195", nome: "Loja X"}].each do |tomador|
      xml = dps(tomador: tomador, ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc)
      assert_nothing_raised {NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)}
    end
    xml = NfseNacional::Dps.new(**RENTAL_GOLDEN_ATTRIBUTES, ibs_cbs: IBS_CBS).to_xml(leiaute: :rtc)
    assert_nothing_raised {NfseNacional::Schema.validate_dps!(xml, leiaute: :rtc)}
  end

  test "rtc sem IBS CBS completo levanta erro claro (cópia alternativa)" do
    [nil, {}, IBS_CBS.merge(cst: ""), IBS_CBS.except(:c_class_trib)].each do |ibs_cbs|
      error = assert_raises(NfseNacional::IbsCbsNaoConfigurado) {dps(ibs_cbs: ibs_cbs).to_xml(leiaute: :rtc)}
      assert_equal "IBS/CBS não configurado", error.message
      refute dps(ibs_cbs: ibs_cbs).ibs_cbs_configured?
    end
    assert dps(ibs_cbs: IBS_CBS).ibs_cbs_configured?
    assert_nothing_raised {dps(ibs_cbs: nil).to_xml}
  end

  private

  def rental_dps(op_simp_nac:, tot_trib:)
    NfseNacional::Dps.new(ambiente: :homologacao,
      prestador: {cnpj: "11222333000181", im: nil, nome: "Empresa Exemplo Ltda", municipio_ibge: "5300108",
                  op_simp_nac: op_simp_nac, reg_ap_trib_sn: ((op_simp_nac == "3") ? "1" : nil), reg_esp_trib: "0"},
      tomador: {documento: "52998224725", nome: "Cliente Teste", email: "c@example.com"},
      servico: RENTAL_SERVICO,
      valores: {valor: "45.00", trib_issqn: "4", tp_ret_issqn: "1", pis_cofins: nil, tot_trib: tot_trib},
      competencia: Date.new(2026, 11, 3), serie: "900", numero: "12345", now: Time.utc(2026, 11, 3, 12))
  end

  def dps(**overrides)
    NfseNacional::Dps.new(**@attributes.merge(overrides))
  end

  def document(xml)
    Nokogiri::XML(xml)
  end

  def namespaces
    {"n" => "http://www.sped.fazenda.gov.br/nfse"}
  end

  def text(tag, **overrides)
    document(dps(**overrides).to_xml).at_xpath("//n:#{tag}", namespaces)&.text
  end
end
