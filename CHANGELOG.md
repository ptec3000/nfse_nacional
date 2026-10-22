# Changelog

## 0.2.0

- CNPJ alfanumérico (IN RFB 2.229/2024) no prestador e no tomador do leiaute `:rtc`, inclusive no Id da DPS. No leiaute `:atual` (XSD 1.00, só números), `to_xml` levanta `ArgumentError`.
- Novo `NfseNacional::Documento`: `normalizar`, `cpf?`, `cnpj?`, `alfanumerico?` e `valido?` (dígitos verificadores de CPF e CNPJ, numérico ou alfanumérico).
- A DPS recusa (`ArgumentError`) documento de tomador brasileiro que não seja CPF (11 dígitos) nem CNPJ (14 posições), em qualquer leiaute, e CNPJ alfanumérico do tomador com dígito verificador inválido (CPF e CNPJ numérico continuam sem conferência de dígito).
- Cancelamento com CNPJ alfanumérico do autor levanta `ArgumentError`: o XSD de eventos 1.00 só aceita números e a gem ainda não tem o de eventos do `:rtc`.
- A normalização do documento passa a manter letras (em maiúsculas) em vez de descartá-las: DPS, `Cancelamento` e a chave de idempotência do `Client#cancelar`. CPF e CNPJ numéricos geram o mesmo XML e a mesma chave de antes.

## 0.1.2

- Leiaute `:rtc` passa a usar os XSDs oficiais da produção restrita de 20/10/2026 (NT 009), sem alterações; sai a cópia derivada (`PATCH.md`). Origem e hash em `schemas/rtc/ORIGEM.md`.
- Teste do padrão de série do leiaute `:rtc` (aceita 49999, recusa 99999).

## 0.1.1

- Teste da margem de segurança do `dhEmi` com o relógio real, trazido do script de emissão original.
- README: seção "Origem e agradecimentos".

## 0.1.0

- Primeira versão do cliente Ruby da NFS-e Nacional.
