module NfseNacional
  class Error < StandardError; end

  class IbsCbsNaoConfigurado < Error
    def initialize(message = "IBS/CBS não configurado") = super
  end
end
