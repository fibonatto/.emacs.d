#!/usr/bin/env bash
# uso: ./salvar-remotes.sh [diretorio] [saida.txt]

dir="${1:-.}"
out="${2:-repos.txt}"

: > "$out"

for repo in "$dir"/*/; do
    [ -e "$repo/.git" ] || continue
    url=$(git -C "$repo" remote get-url origin 2>/dev/null)
    if [ -z "$url" ]; then
        echo "sem remote origin: $repo" >&2
        continue
    fi
    printf '%s\t%s\n' "$(basename "$repo")" "$url" >> "$out"
done

echo "Salvo em $out ($(wc -l < "$out") repositórios)"