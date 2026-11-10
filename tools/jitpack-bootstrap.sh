#!/usr/bin/env bash
# JitPack/干净机器引导脚本。
#
# 为什么需要它：根 pom 的 <dependencyManagement> 里 import 了本 reactor 自己的两个
# BOM（agentscope-dependencies-bom / agentscope-bom），版本都写 ${revision}。
# Maven（3.8.9 与 3.9.11 实测均如此）在建模阶段解析 import 时**只查仓库、不查 reactor**，
# 所以只要该版本号在本地仓里不存在，`mvn install` 会在 "Some problems were encountered
# while processing the POMs" 直接失败，一个模块都编不到。
#
# 本脚本把这三份 pom 按目标版本号写进本地仓，让根 pom 的 import 能解析；
# 随后正常 `mvn install` 会用真实产物覆盖它们。
#
# 用法：bash tools/jitpack-bootstrap.sh [版本号]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

V="${1:-$(sed -n 's:.*<revision>\(.*\)</revision>.*:\1:p' pom.xml | head -1)}"
[ -n "$V" ] || { echo "!! 取不到 revision"; exit 1; }

OUT="$ROOT/target/jitpack-bootstrap"
rm -rf "$OUT"
mkdir -p "$OUT"

cat >"$OUT/bootstrap-pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.bootstrap</groupId>
  <artifactId>bootstrap</artifactId>
  <version>1</version>
  <packaging>pom</packaging>
</project>
EOF

MVN="${MVN:-mvn}"
# 本地测试需要时可传 -Dmaven.repo.local=... ；JitPack 上留空走默认 ~/.m2/repository
MVN_ARGS="${MVN_ARGS:-}"

for entry in "agentscope-parent:pom.xml" \
             "agentscope-dependencies-bom:agentscope-dependencies-bom/pom.xml" \
             "agentscope-bom:agentscope-distribution/agentscope-bom/pom.xml"; do
  aid="${entry%%:*}"
  src="${entry#*:}"
  out="$OUT/$aid-$V.pom"
  sed "s|\${revision}|$V|g" "$src" >"$out"
  # shellcheck disable=SC2086
  "$MVN" -B -q -f "$OUT/bootstrap-pom.xml" $MVN_ARGS install:install-file \
    -Dfile="$out" -DpomFile="$out" -Dpackaging=pom
  echo "bootstrap: $aid:$V"
done

echo "bootstrap done (revision=$V)"
