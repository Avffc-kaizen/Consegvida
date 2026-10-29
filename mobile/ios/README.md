# ConsegVida — iOS com xtool

Cliente SwiftUI nativo, iOS 17+, para o manifesto ConsegVida. O identificador `com.consegvida.app` é provisório e ainda precisa ser verificado na conta Apple do titular. Versão 0.1.0, build 1.

## Conteúdo e persistência

O conteúdo deriva de `../shared/content.json`. O script de sincronização da raiz deve gerar `Sources/ConsegVida/Resources/content.json` e o fixture do pacote `../core-swift`. Não edite essas cópias manualmente. O ícone PNG em `Assets/AppIcon.png` deriva do favicon do repositório.

O estado v1 fica em `ApplicationSupport/ConsegVida/progress-v1.json`, com escrita atômica, proteção completa de arquivo no iOS e exclusão explícita de backup para diretório e arquivo. A UI só atualiza o progresso após salvar com sucesso. Erros de leitura, corrupção ou versões desconhecidas preservam o arquivo e suspendem novas gravações; a pessoa escolhe tentar novamente ou confirmar a exclusão.

Sem rede para progresso, conta, SDK de anúncios, coleta de dados, HealthKit, notificações ou API de IA. O link para o manifesto só abre o YouTube por ação explícita. O dia local é gregoriano, recalculado ao entrar em foreground, mudar o fuso e registrar uma ação.

## Testar o domínio sem Apple SDK

Com Swift 6 instalado, na pasta `mobile/core-swift`:

```bash
swift test
```

Os testes usam arquivos reais temporários e cobrem o contrato de conteúdo, datas, idempotência, necessidade de iniciar a missão, persistência, corrupção, falha de escrita e recuperação. Eles não comprovam UI, assinatura, instalação ou publicação.

## Compilar e testar iOS

Requer [xtool 1.24.0](https://github.com/xtool-org/xtool/releases/tag/1.24.0), Swift e o SDK Apple configurado legitimamente conforme a [documentação oficial](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md). As credenciais Apple não devem entrar no repositório ou em argumentos de comando.

Da pasta `mobile/ios`, quando o SDK estiver disponível:

```bash
xtool dev build
xtool dev build --configuration release --ipa
```

O primeiro comando compila e empacota; o segundo gera IPA sem assinatura para inspeção. Para instalação em aparelho conectado, após o titular configurar autenticação/dispositivo com segurança, o comando oficial é `xtool dev`.

Não executar autenticação, assinatura ou instalação em CI sem ambiente dedicado e autorização adequada. A instalação de desenvolvimento no aparelho não equivale a publicação na App Store.

## Distribuição

O xtool 1.24.0 estável assina com perfis de desenvolvimento; não há aqui promessa de IPA pronta para App Store. Em 29/10/2026, os PRs oficiais [#326](https://github.com/xtool-org/xtool/pull/326) (distribuição) e [#327](https://github.com/xtool-org/xtool/pull/327) (upload) ainda estavam abertos. Não depender de forks experimentais para um lançamento de produção.

Com SDK disponível, `xtool dev generate-xcode-project` é o comando oficial para gerar um projeto Xcode. Em macOS, validar o projeto gerado, configurar equipe/identificador/assets, compilar para simulador, executar testes manuais, fazer archive/export com identidade de distribuição e submeter pelo fluxo oficial Apple. O `iconPath` em xtool é suficiente para o desenvolvimento, mas é necessário confirmar o asset catalog e todos os ícones no archive de distribuição.

Antes do lançamento: validar em iPhone/iPad as cinco abas, começar/concluir/reabrir, idempotência, mudança de dia/fuso, corrupção/recuperação, exclusão, VoiceOver, texto ampliado, rotação, link externo e ausência de coleta. A declaração de privacidade deve ser conferida novamente sobre o binário final e seus SDKs.

## Estado da entrega

Este diretório contém código e configuração de desenvolvimento. Consultar o relatório de validação da raiz para os comandos realmente executados. Não considerar este README evidência de compilação iOS, IPA assinada, teste em aparelho, aprovação ou publicação.
