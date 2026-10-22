module NfseNacional
  # CPF e CNPJ, inclusive o CNPJ alfanumérico (IN RFB 2.229/2024): 12 posições [0-9A-Z]
  # seguidas de 2 dígitos verificadores numéricos.
  module Documento
    CPF = /\A[0-9]{11}\z/
    CNPJ = /\A[0-9A-Z]{12}[0-9]{2}\z/

    module_function

    # Maiúsculas e só [0-9A-Z]; nil quando não sobra nada.
    def normalizar(valor)
      normalizado = valor.to_s.upcase.gsub(/[^0-9A-Z]/, "")
      normalizado.empty? ? nil : normalizado
    end

    def cpf?(valor) = CPF.match?(normalizar(valor).to_s)

    def cnpj?(valor) = CNPJ.match?(normalizar(valor).to_s)

    def alfanumerico?(valor) = cnpj?(valor) && normalizar(valor).match?(/[A-Z]/)

    # Confere os dígitos verificadores; sequências repetidas (111.111.111-11) não valem.
    def valido?(valor)
      documento = normalizar(valor).to_s
      return false if documento.squeeze.length == 1

      if cpf?(documento)
        digitos_conferem?(documento, 9, [10, 11])
      elsif cnpj?(documento)
        digitos_conferem?(documento, 12, [nil, nil])
      else
        false
      end
    end

    # Cada caractere vale o código ASCII menos 48 ('0'..'9' = 0..9, 'A' = 17 ... 'Z' = 42).
    # CPF: pesos decrescentes a partir de 10 e 11. CNPJ: pesos 2..9 da direita para a esquerda, repetindo.
    def digitos_conferem?(documento, tamanho_base, pesos_iniciais)
      base = documento[0, tamanho_base]
      pesos_iniciais.each do |peso_inicial|
        soma = base.chars.each_with_index.sum do |caractere, indice|
          peso = peso_inicial ? peso_inicial - indice : 2 + (base.length - 1 - indice) % 8
          (caractere.ord - 48) * peso
        end
        resto = soma % 11
        base += ((resto < 2) ? 0 : 11 - resto).to_s
      end
      base == documento
    end
    private_class_method :digitos_conferem?
  end
end
