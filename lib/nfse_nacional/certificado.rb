require "openssl"

module NfseNacional
  class Certificado
    class Invalid < StandardError; end

    attr_reader :certificate, :key

    def initialize(pfx:, senha:)
      pkcs12 = parse_pkcs12(pfx, senha)
      @certificate = pkcs12.certificate
      @key = pkcs12.key
      raise Invalid, "Certificado A1 deve conter certificado e chave RSA" unless certificate && key.is_a?(OpenSSL::PKey::RSA)
      raise Invalid, "o certificado e a chave do arquivo não combinam" unless certificate.check_private_key(key)
    end

    def cnpj
      common_name = certificate.subject.to_a.find {|name, _value, _type| name == "CN"}&.at(1)
      common_name&.match(/:(\d{14})\z/)&.[](1)
    end

    def valid_until
      certificate.not_after
    end

    def expired?(at = Time.now)
      at >= valid_until
    end

    private

    def parse_pkcs12(pfx, senha)
      retried = false
      begin
        OpenSSL::PKCS12.new(pfx, senha)
      rescue OpenSSL::PKCS12::PKCS12Error => error
        unless error.message.downcase.include?("unsupported")
          raise Invalid, "Não foi possível abrir o certificado A1: arquivo inválido ou senha incorreta"
        end
        raise Invalid, legacy_format_message if retried

        retried = true
        load_legacy_providers
        retry
      end
    end

    def load_legacy_providers
      # A1 antigos usam RC2/3DES; o Ruby do mise pode não incluir legacy.so,
      # embora o módulo esteja instalado pelo sistema. Preserve a configuração explícita.
      unless ENV.key?("OPENSSL_MODULES")
        directory = %w[
          /usr/lib/x86_64-linux-gnu/ossl-modules
          /usr/lib/aarch64-linux-gnu/ossl-modules
          /usr/lib/ossl-modules
          /usr/local/lib/ossl-modules
        ].find {|path| File.file?(File.join(path, "legacy.so"))}
        ENV["OPENSSL_MODULES"] = directory if directory
      end
      OpenSSL::Provider.load("legacy")
      OpenSSL::Provider.load("default")
    rescue OpenSSL::Provider::ProviderError
      raise Invalid, legacy_format_message
    end

    def legacy_format_message
      "Certificado em formato antigo (RC2/3DES) que este servidor não consegue abrir. Reexporte o .pfx com criptografia AES ou fale com o suporte."
    end
  end
end
