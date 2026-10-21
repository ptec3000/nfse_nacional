require_relative "test_helper"

class NfseNacionalSchemasPresentTest < NfseNacional::TestCase
  ROOT = File.expand_path("../lib/nfse_nacional/schemas", __dir__)

  test "XSDs dos dois leiautes e do evento estão na gem" do
    %w[DPS_v1.00.xsd pedRegEvento_v1.00.xsd rtc/DPS_v1.01.xsd 1.01/DPS_v1.01.xsd rtc/PATCH.md].each do
      assert File.file?(File.join(ROOT, it)), "falta #{it}"
    end
  end

  test "constantes da v0.1" do
    assert_equal "nfse_nacional", NfseNacional::VER_APLIC
    assert_equal({producao: "1", homologacao: "2"}, NfseNacional::AMBIENTES)
    assert_raises(ArgumentError) { NfseNacional.ver_aplic!("x" * 21) }
    assert_equal "x" * 20, NfseNacional.ver_aplic!("x" * 20)
    assert_equal "OutroApp-1", NfseNacional.ver_aplic!("OutroApp-1")
  end
end
