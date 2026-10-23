module NfseNacional
  class CodigosMunicipais
    attr_reader :codigos

    def initialize(exige:, codigos:)
      @exige = exige
      @codigos = codigos.map { it.dup.freeze }.freeze
      freeze
    end

    def exige? = @exige
  end
end
