require "digest"

module NfseNacional
  module Numero
    def self.from_reference(reference)
      number = Digest::SHA256.hexdigest(reference.to_s).to_i(16) % 10**12
      ((number == 0) ? 1 : number).to_s
    end
  end
end
