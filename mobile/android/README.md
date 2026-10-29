# ConsegVida — Android nativo

Primeira fatia funcional em Java 17, com `Activity` e controles nativos do Android.
O identificador provisório é `com.consegvida.app`; versão `0.1.0`, código `1`.
Não há dependências de execução de terceiros, permissão de internet, contas,
anúncios ou envio do progresso a servidores.

## Conteúdo e produto

As telas Hoje, Missões, Minha jornada e Sobre preservam a Fase 1 e os três eixos.
`app/build.gradle` inclui `../../shared` como diretório de assets, relativo ao
módulo `app`, portanto o APK recebe exatamente `mobile/shared/content.json`.
O manifesto só é aberto por ação explícita, com aviso, em outro aplicativo.

## Estado local

- `ProgressState`: transições imutáveis, IDs conhecidos, datas Gregorianas locais
  estritas, conclusão idempotente por missão/dia e limite de 10.000 registros.
- `StateCodec`: JSON v1 estrito; rejeita duplicações, chaves desconhecidas, versões
  incompatíveis, datas/IDs inválidos e conteúdo excedente.
- `StateStore`: no máximo 1 MiB, UTF-8 estrito, escrita em arquivo temporário,
  sincronização do conteúdo e substituição atômica. Não há fallback destrutivo.
- `MainActivity`: somente atribui o próximo estado após salvar com sucesso.
  Corrupção e falha de leitura bloqueiam mutações normais e apresentam recuperação
  visível. Apagar o progresso exige confirmação explícita.
- O reset confirmado limpa arquivos temporários órfãos do próprio armazenamento
  (`.progress-` + número + `.tmp`) antes de substituir o histórico. Não segue links,
  não remove diretórios nem arquivos alheios. Falhas interrompem a limpeza e são
  mostradas; o arquivo principal permanece preservado até a substituição atômica.
- O arquivo fica em `getNoBackupFilesDir()/progress-v1.json`, com backup e
  transferência entre aparelhos excluídos também nos manifests/regras.
- A data é reavaliada em cada ação e o estado é relido ao retornar ao aplicativo.
  O histórico tem páginas de 50 registros e não inventa sequências ou impacto.

## Verificação do núcleo sem SDK Android

```sh
./test-core.sh
```

Requer Java 17 com compilador. O script aceita `javac` ou o módulo
`jdk.compiler` quando o launcher `javac` não estiver no PATH. Os testes exercitam
datas inválidas e futuras, conclusão sem iniciar, duplicação, round-trip,
leitura/gravação real, corrupção, UTF-8 inválido, arquivo excessivo, falha de
substituição atômica, destino de escrita inválido e reset persistido.

## Compilar e verificar o APK

Requisitos: JDK 17, Android SDK plataforma 36 e Build Tools já instalados sob
termos aceitos pelo responsável. O projeto não aceita termos automaticamente.

```sh
./gradlew --no-daemon :app:assembleDebug :app:lintDebug
```

APK de desenvolvimento: `app/build/outputs/apk/debug/app-debug.apk`.
Um APK debug usa chave de desenvolvimento e não é um lançamento na Google Play.
A assinatura de distribuição e a configuração da conta da loja não estão aqui.

## Ferramentas pinadas

- Android Gradle Plugin `8.13.2`, compatível com JDK 17 e SDK 36.
- Gradle `8.13` com wrapper gerado pela distribuição oficial.
- SHA-256 da distribuição:
  `20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`.
- SHA-256 do wrapper JAR:
  `81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f`.

Referências oficiais:
[compatibilidade AGP](https://developer.android.com/build/releases/agp-8-13-0-release-notes),
[checksums Gradle](https://gradle.org/release-checksums/).

## Validação ainda necessária em aparelho

Executar iniciar/concluir/reabrir, troca de dia local, navegação Voltar, cancelamento
do reset, corrupção recuperável, fonte ampliada e TalkBack. Os testes Java não
substituem a validação visual ou em dispositivo Android.

O smoke de UI em emulador pode ser executado depois de instalar o APK debug:

```sh
ANDROID_SERIAL=emulator-5554 python3 smoke-emulator.py --output build/smoke-artifacts
```

O script recusa aparelhos físicos, confirma `ro.kernel.qemu=1` e apaga somente
os dados do pacote `com.consegvida.app` no emulador selecionado para começar um
cenário determinístico. Exercita missão mental, conclusão, reinício real do
processo, preservação após cancelar reset e remoção após confirmar. Salva capturas,
XMLs da UI e resultado JSON. Esse cenário não envia dados a terceiros.
