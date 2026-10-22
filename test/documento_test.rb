require_relative "test_helper"

class NfseNacionalDocumentoTest < NfseNacional::TestCase
  Documento = NfseNacional::Documento

  test "normalizar tira pontuação e espaços e passa para maiúsculas" do
    assert_equal "12ABC34501DE35", Documento.normalizar(" 12.abc.345/01de-35 ")
    assert_equal "12345678000195", Documento.normalizar("12.345.678/0001-95")
    assert_equal "52998224725", Documento.normalizar("529.982.247-25")
    assert_equal "52998224725", Documento.normalizar(52998224725)
  end

  test "normalizar devolve nil quando não sobra nada" do
    [nil, "", "   ", " .-/ "].each { |value| assert_nil Documento.normalizar(value) }
  end

  test "cpf e cnpj pelo formato" do
    assert Documento.cpf?("529.982.247-25")
    assert_not Documento.cpf?("5299822472")
    assert_not Documento.cpf?("5299822472A")
    assert Documento.cnpj?("12.345.678/0001-95")
    assert Documento.cnpj?("12.ABC.345/01DE-35")
    assert_not Documento.cnpj?("12ABC34501DEAB")
    assert_not Documento.cnpj?("1234567800019")
    assert_not Documento.cnpj?(nil)
  end

  test "alfanumérico é o CNPJ com alguma letra" do
    assert Documento.alfanumerico?("12.abc.345/01de-35")
    assert_not Documento.alfanumerico?("12.345.678/0001-95")
    assert_not Documento.alfanumerico?("ABC")
    assert_not Documento.alfanumerico?(nil)
  end

  test "exemplo oficial da Receita de CNPJ alfanumérico é válido" do
    assert Documento.valido?("12.ABC.345/01DE-35")
    assert Documento.valido?("12abc34501de35")
  end

  test "CNPJ alfanumérico com dígito verificador trocado é inválido" do
    assert_not Documento.valido?("12ABC34501DE36")
    assert_not Documento.valido?("12ABC34501DE53")
    assert_not Documento.valido?("12ABD34501DE35")
  end

  test "CNPJ numérico válido e inválido" do
    %w[11222333000181 12.345.678/0001-95].each { |value| assert Documento.valido?(value), value }
    %w[11222333000182 12345678000196].each { |value| assert_not Documento.valido?(value), value }
  end

  test "CPF válido e inválido" do
    %w[529.982.247-25 12345678909].each { |value| assert Documento.valido?(value), value }
    %w[52998224724 12345678900].each { |value| assert_not Documento.valido?(value), value }
  end

  test "sequências repetidas são inválidas" do
    %w[111.111.111-11 00000000000 00000000000000 11111111111111].each do |value|
      assert_not Documento.valido?(value), value
    end
  end

  test "tamanhos e formatos errados são inválidos" do
    [nil, "", "123", "5299822472", "529982247250", "1234567800019", "123456780001950", "12ABC34501DEAB", "ABC"].each do |value|
      assert_not Documento.valido?(value), value.inspect
    end
  end
end
