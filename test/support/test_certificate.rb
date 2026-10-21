require "openssl"

module NfseTestCertificate
  def self.pfx(cnpj: "12345678000195", password: "teste", not_after: Time.utc(2030, 1, 1), name: "EMPRESA TESTE")
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = OpenSSL::X509::Name.new([["CN", cnpj ? "#{name}:#{cnpj}" : name]])
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = Time.utc(2020, 1, 1)
    certificate.not_after = not_after
    certificate.sign(key, OpenSSL::Digest.new("SHA256"))
    OpenSSL::PKCS12.create(password, "Empresa teste", key, certificate).to_der
  end
end
