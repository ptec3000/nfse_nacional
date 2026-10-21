require_relative "test_helper"

class NfseNacionalDpsForeignTomadorTest < NfseNacional::TestCase
  test "tomador estrangeiro sem nome é incompleto mesmo sem documento" do
    error = assert_raises(ArgumentError) do
      NfseNacional::Dps.new(
        ambiente: :homologacao, prestador: {},
        tomador: {nome: "  ", endereco: {pais: "US"}},
        servico: {}, valores: {}, competencia: Date.new(2026, 6, 9), serie: "900", numero: "1"
      )
    end

    assert_match "Tomador incompleto", error.message
  end
end
