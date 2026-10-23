require_relative "nfse_nacional/version"

module NfseNacional
  DHEMI_SAFETY_SECONDS = 5
  AMBIENTES = {producao: "1", homologacao: "2"}.freeze
  VER_APLIC = "nfse_nacional"
  VER_APLIC_MAX = 20

  # O TSVerAplic da Sefin aceita no máximo 20 caracteres; nada além disso é validado aqui.
  def self.ver_aplic!(value)
    raise ArgumentError, "ver_aplic com mais de #{VER_APLIC_MAX} caracteres: #{value}" if value.to_s.length > VER_APLIC_MAX

    value
  end
end

require_relative "nfse_nacional/documento"
require_relative "nfse_nacional/numero"
require_relative "nfse_nacional/dps"
require_relative "nfse_nacional/schema"
require_relative "nfse_nacional/certificado"
require_relative "nfse_nacional/signer"
require_relative "nfse_nacional/error"
require_relative "nfse_nacional/result"
require_relative "nfse_nacional/cancelamento"
require_relative "nfse_nacional/codigos_municipais"
require_relative "nfse_nacional/client"
