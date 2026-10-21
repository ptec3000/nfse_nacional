require_relative "lib/nfse_nacional/version"

Gem::Specification.new do |spec|
  spec.name = "nfse_nacional"
  spec.version = NfseNacional::VERSION
  spec.authors = ["Acervo Tecnologia"]
  spec.email = ["pedro@acervotecnologia.com.br"]
  spec.summary = "Cliente Ruby da NFS-e Nacional (Sefin): DPS, XSD, assinatura, emissão, consulta e cancelamento"
  spec.description = "Monta a DPS, valida nos XSDs oficiais, assina com o certificado A1 e conversa com a API da Sefin Nacional. Sem Rails."
  spec.homepage = "https://github.com/ptec3000/nfse_nacional"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata = {
    "source_code_uri" => "https://github.com/ptec3000/nfse_nacional",
    "changelog_uri" => "https://github.com/ptec3000/nfse_nacional/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/ptec3000/nfse_nacional/issues",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"].select { File.file?(it) }
  end
  spec.add_dependency "nokogiri", "~> 1.16"
  spec.add_dependency "bigdecimal"
  spec.add_dependency "base64"
end
