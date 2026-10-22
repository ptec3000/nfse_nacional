# nfse_nacional

[![CI](https://github.com/ptec3000/nfse_nacional/actions/workflows/ci.yml/badge.svg)](https://github.com/ptec3000/nfse_nacional/actions/workflows/ci.yml)

**Emite, consulta e cancela NFS-e Nacional em Ruby puro, sem Rails.**

Monta a DPS, valida nos XSDs oficiais, assina com o certificado A1 e conversa com a API da Sefin Nacional. Não gera PDF; para gerar o documento a partir do XML autorizado, use a gem [`danfse`](https://github.com/ptec3000/danfse).

> 🎲 **Testada em produção.** Emite, consulta e cancela as notas fiscais da [Acervo de Jogos](https://www.acervodejogos.com.br), plataforma para aluguel de jogos de tabuleiro.

## O que ela cobre

- Leiautes `:atual` (XSD 1.00) e `:rtc` (1.01 com IBS/CBS, NT 009, com os esquemas oficiais da produção restrita de 20/10/2026; origem em [`ORIGEM.md`](lib/nfse_nacional/schemas/rtc/ORIGEM.md)).
- Tomador no Brasil e no exterior, inclusive comércio exterior.
- Simples Nacional e regime normal.
- Emissão com chave de idempotência, consulta de DPS e de NFS-e e cancelamento.
- Assinatura XMLDSig com certificado A1.

## Começo rápido

Requer Ruby 3.4 ou superior. No Gemfile:

```ruby
gem "nfse_nacional", github: "ptec3000/nfse_nacional", tag: "v0.1.2"
```

Depois, `bundle install` e:

```ruby
require "date"
require "nfse_nacional"

certificado = NfseNacional::Certificado.new(
  pfx: File.binread("certificado.pfx"), senha: ENV["SENHA"]
)

dps = NfseNacional::Dps.new(
  ambiente: :homologacao,
  prestador: {cnpj: "12345678000195", municipio_ibge: "3106200", op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
  tomador: {documento: "12345678909", nome: "Cliente Exemplo", email: "cliente@example.com"},
  servico: {c_trib_nac: "010501", municipio_prestacao_ibge: "3106200", descricao: "Serviço de exemplo", nbs: "111032200"},
  valores: {valor: "100.00", trib_issqn: "1", tp_ret_issqn: "1", pis_cofins: nil},
  competencia: Date.new(2026, 10, 20), serie: "900", numero: "1", now: Time.now - 60,
  ver_aplic: "MeuApp-1"
)

client = NfseNacional::Client.new(
  certificado: certificado, ambiente: :homologacao, ver_aplic: "MeuApp-1"
)
result = client.emitir(dps, idempotency_key: dps.id)

case result.status
when :issued
  File.write("nota.xml", result.nfse_xml)
  puts result.access_key
when :rejected
  warn result.errors.join("; ") # corrija os dados antes de emitir de novo
when :error
  warn result.errors.join("; ") # tente depois, com a mesma chave de idempotência
end
```

Guarde a DPS e a chave de idempotência para reutilizá-las nas novas tentativas. Para IBS/CBS, passe `ibs_cbs: {c_ind_op: "030101", cst: "000", c_class_trib: "000001"}` à DPS e `leiaute: :rtc` a `emitir`. Use dados e certificado próprios ao integrar; os valores acima são exemplos de homologação.

## Consultar e cancelar

Com o mesmo `client`:

```ruby
consulta = client.consultar_dps(dps.id)

case consulta.status
when :issued
  chave = consulta.access_key
  nota = client.consultar_nfse(chave)
  case nota.status
  when :issued
    File.write("nota.xml", nota.nfse_xml)
    # Com a gem danfse instalada e require "danfse":
    # File.binwrite("nota.pdf", Danfse.render(nota.nfse_xml))
  when :not_found
    warn "NFS-e não encontrada. Confira a chave."
  when :rejected
    warn "A Sefin recusou a consulta. Isso não prova que a nota não existe; investigue e tente de novo depois."
  when :error
    warn "Falha de rede ou da Sefin. Tente de novo."
  end

  cancelamento = client.cancelar(
    chave, cnpj_autor: "12345678000195",
    motivo: "Erro na emissão da nota de teste"
  )
  warn cancelamento.errors.join("; ") unless cancelamento.status == :issued
when :not_found
  warn "A DPS/NFS-e não existe. Confira o identificador."
when :rejected
  warn "A Sefin recusou a consulta. Isso não prova que a nota não existe; investigue e tente de novo depois."
when :error
  warn "Falha de rede ou da Sefin. Tente de novo."
end
```

`consultar_nfse` devolve um resultado com `nfse_xml`, o XML autorizado que pode ser entregue à [`danfse`](https://github.com/ptec3000/danfse). Confira o `status` de cada operação antes de usar o XML ou a chave de acesso.

## Resultado e novas tentativas

| `status` | Quando acontece | O que fazer |
| --- | --- | --- |
| `:issued` | Nota emitida, consulta achou a DPS/NFS-e, ou evento registrado. | Guarde a chave de acesso e o XML retornado (`nfse_xml` ou `event_xml`). |
| `:rejected` em emissão ou cancelamento | A Sefin recusou o conteúdo (ex.: E1235). | Corrija os dados; repetir o mesmo XML não resolve. |
| `:rejected` em consulta | A Sefin recusou a consulta (ex.: 403 E2403). | Isso **não prova** que a nota não existe: investigue o erro e deixe o usuário tentar de novo depois. |
| `:error` | Rede, 5xx, 408 ou 429. | Tente de novo; na emissão, use a mesma chave de idempotência. |
| `:not_found` | Só em consulta: a DPS/NFS-e não existe. | Confira o identificador consultado antes de decidir o próximo passo. |

`retryable?` é verdadeiro só para `:error`. O resultado também expõe `errors`, `http_status`, `body` e `request_xml` para diagnóstico.

## `ver_aplic`

Informe o nome do seu app, com até 20 caracteres, em `Dps.new` e `Client.new`. O padrão é `"nfse_nacional"`; valores maiores geram `ArgumentError`. A DPS usa esse valor na emissão e o cliente o usa no pedido de cancelamento.

## Quando a Sefin muda o leiaute

O leiaute `:rtc` acompanha a versão 1.01 com IBS/CBS da reforma tributária (NT 009). Os XSDs são os oficiais da produção restrita publicados em 20/10/2026, sem alterações; a origem e o hash do pacote estão em [`schemas/rtc/ORIGEM.md`](lib/nfse_nacional/schemas/rtc/ORIGEM.md). Segundo o Comitê Gestor, essa versão entra em produção em 01/12/2026.

Para atualizar: acrescente uma fixture com XML que a Sefin aceitou, sem dados reais de pessoas, e um teste que cubra o caso. Publique uma versão nova da gem com o ajuste e os apps passam a usar a nova tag. Assim cada app escolhe quando adotar a mudança.

## Contribuindo

```sh
bundle install
bundle exec rake test
bundle exec standardrb # estilo; não obrigatório na CI
```

Envie mudanças por pull request com versão nova: atualize o `CHANGELOG.md` e `NfseNacional::VERSION`. Inclua testes que reproduzam a mudança. Nunca coloque certificado real nem dados reais de pessoas no repositório.

## Origem e agradecimentos

A base desta gem veio do script de emissão de NFS-e escrito por **Weverson Ferreira do Santos** ([@negowfs](https://github.com/negowfs)): a montagem e a numeração da DPS, o formato do Id, a margem de segurança do `dhEmi`, a assinatura XMLDSig no perfil que a Sefin aceita em produção, o envio compactado em gzip/base64, a chave de idempotência e o primeiro conjunto de XSDs. Obrigado, Nego!

## Licenças

O código é [MIT](LICENSE). Os XSDs são publicados pela Receita Federal/Sefin Nacional; a origem está em [`lib/nfse_nacional/schemas/README.md`](lib/nfse_nacional/schemas/README.md).
