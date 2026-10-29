#!/usr/bin/env python3
"""Publish one tested APK without rebuilding; --prepare-only performs no network operations."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

REPO, TAG = "Avffc-kaizen/Consegvida", "v0.1.0-preview"
BASE = "1dec15df0f2bb87498a05ae348bc22adfd14d7ab"
HEAD = "8633ac429a21c3869bd3fc964ecdb77b80157a0e"
TREE = "d7db99651b30d0c20e3cd56392644cc9908cb4b4"
PUBLISHER = {".github/workflows/mobile-publish-preview.yml", ".github/scripts/publish_android_preview.py"}
RUN, ARTIFACT = 40914666442, 12914859694
ZIP_SHA = "9c66c8ec43952697a00e9669e9662716a0c5730b0ead42cd8598e4db109a3024"
APK_SHA = "18b996136b183b343507ebb337edaf289a17d5895c40febd34b34827ca6fe7d2"
MEMBER, APK = "app/build/outputs/apk/debug/app-debug.apk", "ConsegVida-0.1.0-Android.apk"
TITLE = "ConsegVida 0.1.0 — prévia Android"
README = f"""# ConsegVida 0.1.0 — prévia Android

Baixe {APK} nos arquivos desta versão. Requer Android 8.0 ou posterior.
Este é o APK de desenvolvimento (debug) já testado no CI, assinado com a
chave de depuração daquele build. É uma prévia para testes, sem lançamento
na Google Play. Não foi gerada uma nova compilação para esta publicação.

Para instalar: abra o APK no Android e, se solicitado, permita que o navegador
ou gerenciador de arquivos instale apps desta origem. Siga os avisos do Android.
Depois da instalação, essa permissão pode ser desativada novamente.

O app funciona offline: missões e progresso ficam no aparelho, sem conta,
sincronização ou backup. Links externos só abrem por escolha do usuário.
Desinstalar ou apagar os dados do app elimina o progresso local. Futuras prévias
podem exigir desinstalação antes da instalação, por usarem outra assinatura.

iOS: a compilação foi verificada, mas a distribuição ainda depende da assinatura
Apple e da preparação/publicação pelo TestFlight ou App Store. Esta versão não
contém um aplicativo instalável no iPhone.

Origem: https://github.com/{REPO}/actions/runs/{RUN}
Commit testado: {HEAD}
Base integrada do app: {BASE}
O commit associado à tag inclui apenas a automação de publicação além dessa
base. Consulte a tag desta release para ver o SHA correspondente.
SHA-256 do APK: {APK_SHA}
Confira também SHA256SUMS.txt. Nenhuma chave privada acompanha estes arquivos.
"""


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


TEXTS = {"LEIA-ME.txt": README.encode("utf-8")}
TEXTS["SHA256SUMS.txt"] = (f"{APK_SHA}  {APK}\n{sha(TEXTS['LEIA-ME.txt'])}  LEIA-ME.txt\n").encode()
EXPECTED = {APK: (APK_SHA, 33465), **{n: (sha(b), len(b)) for n, b in TEXTS.items()}}


def gh(*args, data=None):
    return subprocess.run(["gh", *args], input=data, stdout=subprocess.PIPE, check=True).stdout


def api(path, data=None, method="POST"):
    args = ["api", f"repos/{REPO}/{path}", "--method", "GET" if data is None else method]
    return json.loads(gh(*args, *([] if data is None else ["--input", "-"]),
                         data=None if data is None else json.dumps(data).encode()))


def prepare(raw, destination):
    require(len(raw) == 691490 and sha(raw) == ZIP_SHA, "ZIP diferente do artefato aprovado")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(archive.namelist().count(MEMBER) == 1, "Membro APK ausente ou duplicado")
        apk = archive.read(MEMBER)  # Never extract other members or use extractall().
    require((sha(apk), len(apk)) == EXPECTED[APK], "APK diferente do aprovado")
    destination.mkdir(parents=True, exist_ok=True)
    for name, data in {APK: apk, **TEXTS}.items():
        (destination / name).write_bytes(data)


def validate_target(target):
    require(isinstance(target, str) and re.fullmatch(r"[0-9a-f]{40}", target), "Alvo deve ser SHA completo")
    tree = api(f"git/commits/{target}")["tree"]["sha"]
    snapshots = [api(f"git/trees/{sha}?recursive=1") for sha in (TREE, tree)]
    require(all(not s["truncated"] for s in snapshots), "Árvore incompleta; comparação recusada")
    original, candidate = [{f["path"]: (f["mode"], f["type"], f["sha"])
                            for f in s["tree"] if f["type"] != "tree"} for s in snapshots]
    require(not PUBLISHER & original.keys() and candidate.keys() - original.keys() == PUBLISHER
            and {p: v for p, v in candidate.items() if p not in PUBLISHER} == original
            and all(candidate[p][:2] == ("100644", "blob") for p in PUBLISHER),
            "O alvo deve preservar toda a base e acrescentar somente os dois arquivos do publisher")


def verify_release(release, complete, target):
    require(all(release.get(k) == v for k, v in {
        "tag_name": TAG, "target_commitish": target, "name": TITLE,
        "body": README, "prerelease": True}.items()), "Release existente tem metadados diferentes")
    assets = release["assets"]
    names = [a["name"] for a in assets]
    require(len(set(names)) == len(names) and set(names) <= EXPECTED.keys(), "Assets inesperados")
    require(not complete or set(names) == EXPECTED.keys(), "Release incompleta")
    for asset in assets:
        raw = gh("api", f"repos/{REPO}/releases/assets/{asset['id']}", "-H", "Accept: application/octet-stream")
        require((sha(raw), len(raw)) == EXPECTED[asset["name"]], "Asset remoto diferente: " + asset["name"])
    return set(names)


def ensure_tag(target, create=False):
    refs = api(f"git/matching-refs/tags/{TAG}")
    if any(r["ref"] == f"refs/tags/{TAG}" for r in refs):
        require(api(f"commits/{TAG}")["sha"] == target, "Tag existente aponta para outro commit")
    else:
        require(create, "Tag publicada ausente")
        api("git/refs", {"ref": f"refs/tags/{TAG}", "sha": target})  # Ref creation never overwrites.


def publish(destination):
    require(os.environ.get("GITHUB_REPOSITORY") == REPO and os.environ.get("GITHUB_REF") == "refs/heads/main",
            "Publicação permitida somente pelo workflow da main neste repositório")
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{REPO}/releases?per_page=100"))
    existing = [r for page in pages for r in page if r["tag_name"] == TAG]
    require(len(existing) <= 1, "Mais de uma release para a tag")
    release = existing[0] if existing else None
    target = release["target_commitish"] if release else os.environ.get("GITHUB_SHA", "")
    validate_target(target)
    if release and not release["draft"]:
        verify_release(release, True, target)
        ensure_tag(target)
        print("Prévia já publicada e verificada: " + release["html_url"])
        return
    present = verify_release(release, False, target) if release else set()
    run, artifact = api(f"actions/runs/{RUN}"), api(f"actions/artifacts/{ARTIFACT}")
    require(run["id"] == RUN and run["status"] == "completed" and run["conclusion"] == "success"
            and run["head_sha"] == HEAD, "Execução de origem não corresponde ao CI aprovado")
    require(artifact["id"] == ARTIFACT and artifact["name"] == "consegvida-android-preview"
            and not artifact["expired"] and artifact["digest"] == "sha256:" + ZIP_SHA
            and artifact["workflow_run"]["id"] == RUN and artifact["workflow_run"]["head_sha"] == HEAD,
            "Artefato expirado ou diferente do aprovado")
    require(all(api(f"git/commits/{commit}")["tree"]["sha"] == TREE for commit in (HEAD, BASE)),
            "Base do aplicativo não corresponde à árvore testada")
    prepare(gh("api", f"repos/{REPO}/actions/artifacts/{ARTIFACT}/zip"), destination)
    if release is None:
        require(api("git/ref/heads/main")["object"]["sha"] == target,
                "A main avançou desde este workflow; execute novamente a versão atual")
        release = api("releases", {"tag_name": TAG, "target_commitish": target, "name": TITLE,
                                  "body": README, "draft": True, "prerelease": True, "make_latest": "false"})
    missing = [str(destination / name) for name in EXPECTED if name not in present]
    if missing:
        gh("release", "upload", TAG, *missing, "--repo", REPO)  # No --clobber.
    path = f"releases/{release['id']}"
    verify_release(api(path), True, target)
    ensure_tag(target, create=True)
    api(path, {"draft": False, "prerelease": True, "make_latest": "false"}, method="PATCH")
    release = api(path)
    require(not release["draft"], "Release continua como draft")
    verify_release(release, True, target)
    print("Prévia publicada e verificada: " + release["html_url"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", type=Path, metavar="ZIP")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.prepare_only:
        require(args.output is not None, "--prepare-only exige --output")
        prepare(args.prepare_only.read_bytes(), args.output)
        print("APK e instruções verificados e preparados localmente; nenhuma operação remota.")
    else:
        require(args.output is None, "--output exige --prepare-only")
        with tempfile.TemporaryDirectory(prefix="consegvida-preview-") as directory:
            publish(Path(directory))
