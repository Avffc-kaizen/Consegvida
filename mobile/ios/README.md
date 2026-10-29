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

### Archive de device sem assinatura

Em um macOS com Xcode completo selecionado, SDK `iphoneos`, Python 3.9+ e xtool **1.24.0** verificado, executar da raiz do repositório:

```bash
bash mobile/ios/ci-archive-unsigned.sh
```

A variável `CONSEGVIDA_XTOOL_BIN` permite indicar o executável da instalação verificada do xtool. Este script não instala ferramentas. Deve rodar após a sincronização do conteúdo e dos ícones. Uma execução produz saídas em `mobile/ios/build/artifacts/unsigned-ios`; a pasta precisa estar ausente para evitar misturar artefatos de execuções diferentes. Os diagnósticos ficam em `mobile/ios/build/evidence/archive-unsigned`.

O script usa uma cópia isolada dos fontes e preserva a dependência local `../core-swift`. Cria um catálogo `AppIcon` com o PNG canônico de 1024 × 1024 e usa o `actool` do Xcode para gerar as variações iPhone/iPad. A [Apple documenta esse formato de ícone de tamanho único](https://developer.apple.com/documentation/xcode/configuring-your-app-icon). O plist parcial e os recursos compilados entram pelos campos públicos `infoPath` e `resources` do xtool; o `project.pbxproj` gerado não recebe alterações manuais. Esse caminho está baseado no [gerador oficial do tag 1.24.0](https://github.com/xtool-org/xtool/blob/1.24.0/Sources/PackLib/XcodePacker.swift) e nos [argumentos do compilador de assets usados pelo Swift Build](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/Specs/AssetCatalogCompiler.xcspec).

Após `xtool dev generate-xcode-project`, o script descobre o scheme da aplicação e executa `xcodebuild archive` em Release com destino `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO` e equipe/identidade/perfil vazios. Não faz autenticação, provisionamento, assinatura de distribuição, exportação ou upload. Uma eventual assinatura ad hoc inserida pelo linker é registrada separadamente e só é aceita sem identidade/equipe.

O resultado só é empacotado se o archive contiver uma única aplicação de device, Mach-O da plataforma iOS, identificador/versão corretos, ícones processados idênticos à saída do `actool`, metadados de ícone iPhone/iPad, `PrivacyInfo.xcprivacy` igual ao fonte e o conteúdo canônico dentro do bundle SwiftPM. Archives genéricos, resources ausentes ou assinaturas de identidade inesperadas fazem o script falhar. A verificação estrutural segue a distinção da Apple entre [archive de aplicação e archive genérico](https://developer.apple.com/documentation/technotes/tn3110-resolving-generic-xcode-archive-issue).

As saídas são:

- `ConsegVida-unsigned.xcarchive.zip`: archive Release para inspeção e posterior fluxo autorizado de assinatura/exportação.
- `ConsegVida-Xcode-project.zip`: workspace/projeto gerado, fontes dos dois pacotes, conteúdo, catálogo de ícone e recursos compilados, preservando os caminhos relativos. Abra `mobile/ios/xtool/ConsegVida.xcworkspace` após descompactar.
- `archive-validation.json`, `source-sha256.json` e `SHA256SUMS.txt`: escopo, verificações, versões das ferramentas e hashes dos fontes/artefatos.

Esse archive não é uma IPA instalável e não comprova aceitação pela App Store. Confirmar o bundle ID provisório e a equipe do titular, executar aceitação em aparelho, revisar os dados da loja e realizar assinatura/exportação e validação pelo fluxo Apple permanecem gates de lançamento. O projeto inclui os assets já compilados; ao trocar o ícone ou SDK, regenere a partir do script no repositório. A [documentação de distribuição da Apple](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) descreve a validação e exportação posteriores.

Para CI, usar um job macOS próprio ou reservar tempo para uma compilação Release adicional; a duração ainda precisa ser medida no runner. Publicar `build/artifacts/unsigned-ios` apenas quando o script concluir e guardar `build/evidence/archive-unsigned` também em caso de falha. A execução do script em Linux não compila nem simula um archive iOS.

## Estado da entrega

Este diretório contém código e configuração de desenvolvimento. Consultar o relatório de validação da raiz para os comandos realmente executados. Não considerar este README evidência de compilação iOS, IPA assinada, teste em aparelho, aprovação ou publicação.
