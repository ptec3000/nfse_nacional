# Changelog

## 0.1.3

- `cIndOp` passa a ser opcional no grupo IBS/CBS (leiaute `:rtc`): sai do XML quando vem em branco. A homologação da Sefin recusa com E0859 o `cIndOp` em operação sem tributação IBS/CBS (ex.: exportação com CST 410 / cClassTrib 410004), testado em 22/10/2026. `CST` e `cClassTrib` continuam obrigatórios.

## 0.1.2

- Leiaute `:rtc` passa a usar os XSDs oficiais da produção restrita de 20/10/2026 (NT 009), sem alterações; sai a cópia derivada (`PATCH.md`). Origem e hash em `schemas/rtc/ORIGEM.md`.
- Teste do padrão de série do leiaute `:rtc` (aceita 49999, recusa 99999).

## 0.1.1

- Teste da margem de segurança do `dhEmi` com o relógio real, trazido do script de emissão original.
- README: seção "Origem e agradecimentos".

## 0.1.0

- Primeira versão do cliente Ruby da NFS-e Nacional.
