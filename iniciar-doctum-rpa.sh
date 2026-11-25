#!/usr/bin/env bash
# =============================================================================
#  Doctum RPA - Iniciador para Linux
#
#  Uso:
#    ./iniciar-doctum-rpa.sh              desenvolvimento: backend (5678) + Vite (8080)
#    ./iniciar-doctum-rpa.sh --producao   producao: somente backend (5678), UI compilada
#    ./iniciar-doctum-rpa.sh --parar      para os servidores iniciados por este script
#    ./iniciar-doctum-rpa.sh --status     mostra o estado dos servidores
#
#  O projeto e localizado automaticamente (ou defina DOCTUM_RPA_DIR).
#  Logs e PIDs ficam em: ~/.cache/doctum-rpa/
# =============================================================================

set -u

# Idioma padrao da interface. O n8n aceita apenas codigos ISO 639-1,
# portanto use "pt" (e nao "pt-BR").
export N8N_DEFAULT_LOCALE="${N8N_DEFAULT_LOCALE:-pt}"

# Modulos liberados para execucao no no Code (ex: fs, path, crypto).
# Essencial para automacoes RPA locais (manipulacao de arquivos do sistema).
export NODE_FUNCTION_ALLOW_BUILTIN="${NODE_FUNCTION_ALLOW_BUILTIN:-*}"
export NODE_FUNCTION_ALLOW_EXTERNAL="${NODE_FUNCTION_ALLOW_EXTERNAL:-*}"

PORT_BACKEND=5678
PORT_FRONTEND=8080
MODE="dev"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/doctum-rpa"
LOG_BACKEND="$CACHE_DIR/backend.log"
LOG_FRONTEND="$CACHE_DIR/frontend.log"
PID_BACKEND="$CACHE_DIR/backend.pid"
PID_FRONTEND="$CACHE_DIR/frontend.pid"

say() { printf '%s\n' "$*"; }
err() { printf '[ERRO] %s\n' "$*" >&2; }

usage() {
	cat <<'EOF'
Doctum RPA - Iniciador (Linux)

Uso:
  ./iniciar-doctum-rpa.sh                 Inicia backend (5678) + Vite (8080)  [padrao]
  ./iniciar-doctum-rpa.sh --producao      Inicia somente o backend (5678)
  ./iniciar-doctum-rpa.sh --parar         Para os servidores iniciados por este script
  ./iniciar-doctum-rpa.sh --status        Mostra o estado dos servidores
  ./iniciar-doctum-rpa.sh --help          Mostra esta ajuda

Variavel opcional:
  DOCTUM_RPA_DIR=/caminho/do/projeto      Forca a pasta do projeto

Logs: ~/.cache/doctum-rpa/
EOF
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

port_open() {
	local port="$1"
	if command -v ss >/dev/null 2>&1; then
		ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
	elif command -v netstat >/dev/null 2>&1; then
		netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
	else
		(exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
	fi
}

pid_alive() {
	[ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

# Considera pronto somente HTTP 200 (porta aberta nao garante que a UI responde:
# durante a inicializacao o Express pode devolver "Cannot GET /").
http_ok() {
	local url="$1"
	if command -v curl >/dev/null 2>&1; then
		[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)" = "200" ]
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O /dev/null --timeout=5 "$url" >/dev/null 2>&1
	else
		local rest="${url#http://}" host port
		host="${rest%%/*}"
		port="${host##*:}"
		host="${host%%:*}"
		exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null || return 1
		printf 'GET / HTTP/1.0\r\nHost: %s\r\n\r\n' "$host" >&3
		head -n 1 <&3 | grep -q ' 200 '
		local rc=$?
		exec 3<&- 3>&-
		return $rc
	fi
}

find_project() {
	local cand self_dir

	if [ -n "${DOCTUM_RPA_DIR:-}" ]; then
		if [ -f "$DOCTUM_RPA_DIR/packages/cli/bin/n8n" ]; then
			(cd "$DOCTUM_RPA_DIR" && pwd)
			return 0
		fi
	fi

	self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	for cand in "$self_dir" "$self_dir/n8n-master" "$self_dir/doctum-rpa" "$self_dir/.."; do
		if [ -f "$cand/packages/cli/bin/n8n" ]; then
			(cd "$cand" && pwd)
			return 0
		fi
	done

	for cand in \
		"$HOME/doctum-rpa" \
		"$HOME/Documentos/doctum-rpa" \
		"$HOME/Documents/doctum-rpa" \
		"$HOME/Desktop/doctum-rpa" \
		"$HOME/Area de Trabalho/doctum-rpa" \
		"$HOME/Área de Trabalho/doctum-rpa" \
		"$HOME/n8n-master" \
		"$HOME/Documentos/n8n-master" \
		"$HOME/Documents/n8n-master" \
		"$HOME/Desktop/n8n-master" \
		"$HOME/Area de Trabalho/n8n-master" \
		"$HOME/Área de Trabalho/n8n-master"; do
		if [ -f "$cand/packages/cli/bin/n8n" ]; then
			say "$cand"
			return 0
		fi
	done

	return 1
}

start_detached() {
	local dir="$1" log="$2" pidfile="$3"
	shift 3
	mkdir -p "$CACHE_DIR"
	(
		cd "$dir" || exit 1
		nohup "$@" >"$log" 2>&1 &
		echo $! >"$pidfile"
	)
}

stop_one() {
	local pidfile="$1" name="$2" port="$3" pid i=0
	if [ ! -f "$pidfile" ]; then
		if port_open "$port"; then
			say "[--] $name esta rodando, mas nao foi iniciado por este script (nao sera parado)."
		fi
		return 0
	fi
	pid="$(cat "$pidfile" 2>/dev/null)"
	if pid_alive "$pid"; then
		kill -TERM "$pid" 2>/dev/null || true
		while pid_alive "$pid" && [ "$i" -lt 10 ]; do
			sleep 1
			i=$((i + 1))
		done
		if pid_alive "$pid"; then
			kill -KILL "$pid" 2>/dev/null || true
		fi
		say "[OK] $name parado (PID $pid)."
	else
		say "[--] $name nao estava rodando."
	fi
	rm -f "$pidfile"
}

wait_http() {
	local url="$1" timeout="$2" pidfile="${3:-}" waited=0
	while ! http_ok "$url"; do
		if [ "$waited" -ge "$timeout" ]; then
			return 1
		fi
		if [ -n "$pidfile" ] && [ -f "$pidfile" ] && ! pid_alive "$(cat "$pidfile" 2>/dev/null)"; then
			return 2
		fi
		sleep 3
		waited=$((waited + 3))
		if [ $((waited % 30)) -eq 0 ]; then
			say "  ... ${waited}s"
		fi
	done
	return 0
}

open_browser() {
	local url="$1"
	if command -v xdg-open >/dev/null 2>&1; then
		xdg-open "$url" >/dev/null 2>&1 &
	elif command -v gio >/dev/null 2>&1; then
		gio open "$url" >/dev/null 2>&1 &
	elif command -v sensible-browser >/dev/null 2>&1; then
		sensible-browser "$url" >/dev/null 2>&1 &
	elif [ -n "${BROWSER:-}" ]; then
		"$BROWSER" "$url" >/dev/null 2>&1 &
	else
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# Acoes
# ---------------------------------------------------------------------------

do_stop() {
	say "[...] Parando servidores do Doctum RPA..."
	stop_one "$PID_FRONTEND" "Frontend (Vite 8080)" "$PORT_FRONTEND"
	stop_one "$PID_BACKEND" "Backend (n8n 5678)" "$PORT_BACKEND"
	say "[OK] Pronto."
}

do_status() {
	if port_open "$PORT_BACKEND"; then
		say "[ATIVO ] backend  :$PORT_BACKEND"
	else
		say "[PARADO] backend  :$PORT_BACKEND"
	fi
	if port_open "$PORT_FRONTEND"; then
		say "[ATIVO ] frontend :$PORT_FRONTEND"
	else
		say "[PARADO] frontend :$PORT_FRONTEND"
	fi
	[ -f "$PID_BACKEND" ] && say "  pid backend : $(cat "$PID_BACKEND" 2>/dev/null)"
	[ -f "$PID_FRONTEND" ] && say "  pid frontend: $(cat "$PID_FRONTEND" 2>/dev/null)"
	say "  logs        : $CACHE_DIR"
}

do_start() {
	local proj node_bin node_major vite_js vite_bin url

	say "================================================"
	if [ "$MODE" = "dev" ]; then
		say "  Doctum RPA - DESENVOLVIMENTO (backend + Vite)"
		say "  Acesso: http://localhost:${PORT_FRONTEND}"
	else
		say "  Doctum RPA - PRODUCAO (sem Vite)"
		say "  Acesso: http://localhost:${PORT_BACKEND}"
	fi
	say "================================================"

	if ! proj="$(find_project)"; then
		err "Pasta do projeto nao encontrada."
		err "Defina DOCTUM_RPA_DIR=/caminho/do/projeto e tente de novo."
		return 1
	fi
	say "[OK] Projeto: $proj"

	if ! node_bin="$(command -v node)"; then
		err "Node.js nao encontrado no PATH. Instale Node.js 24+."
		return 1
	fi
	node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
	if [ "$node_major" -lt 24 ] 2>/dev/null; then
		say "[AVISO] Node.js $(node -v) detectado; o projeto espera Node.js 24+."
	fi

	if [ "$MODE" = "prod" ]; then
		if [ ! -f "$proj/packages/frontend/editor-ui/dist/index.html" ]; then
			err "Interface nao compilada (dist ausente)."
			err "Compile uma vez:  cd \"$proj/packages/frontend/editor-ui\" && pnpm run build"
			return 3
		fi
		say "[OK] Interface compilada: $(date -r "$proj/packages/frontend/editor-ui/dist/index.html" '+%d/%m/%Y %H:%M' 2>/dev/null || echo 'ok')"
	fi

	# 1) Backend n8n
	if port_open "$PORT_BACKEND"; then
		say "[OK] Backend (${PORT_BACKEND}) ja esta rodando."
	else
		say "[...] Iniciando backend n8n (porta ${PORT_BACKEND})..."
		start_detached "$proj/packages/cli" "$LOG_BACKEND" "$PID_BACKEND" "$node_bin" bin/n8n start
	fi

	# 2) Frontend Vite (somente no modo dev)
	if [ "$MODE" = "dev" ]; then
		if port_open "$PORT_FRONTEND"; then
			say "[OK] Frontend Vite (${PORT_FRONTEND}) ja esta rodando."
		else
			vite_js=""
			if [ -f "$proj/packages/frontend/editor-ui/node_modules/vite/bin/vite.js" ]; then
				vite_js="$proj/packages/frontend/editor-ui/node_modules/vite/bin/vite.js"
			elif [ -f "$proj/node_modules/vite/bin/vite.js" ]; then
				vite_js="$proj/node_modules/vite/bin/vite.js"
			fi

			say "[...] Iniciando frontend Vite (porta ${PORT_FRONTEND})..."
			if [ -n "$vite_js" ]; then
				start_detached "$proj/packages/frontend/editor-ui" "$LOG_FRONTEND" "$PID_FRONTEND" \
					"$node_bin" "$vite_js" dev --port "$PORT_FRONTEND"
			else
				vite_bin="$proj/packages/frontend/editor-ui/node_modules/.bin/vite"
				if [ -x "$vite_bin" ]; then
					start_detached "$proj/packages/frontend/editor-ui" "$LOG_FRONTEND" "$PID_FRONTEND" \
						"$vite_bin" dev --port "$PORT_FRONTEND"
				else
					err "Vite nao encontrado. Rode 'pnpm install' na raiz do projeto."
					return 1
				fi
			fi
		fi
	fi

	# 3) Espera o backend responder HTTP 200 (a 1a execucao pode levar 1-3 min)
	say "[...] Aguardando http://localhost:${PORT_BACKEND} responder 200 (ate 5 min)..."
	wait_http "http://localhost:${PORT_BACKEND}/" 300 "$PID_BACKEND"
	case $? in
	0) say "[OK] Backend no ar! (http://localhost:${PORT_BACKEND})" ;;
	2)
		err "O processo do backend terminou antes de responder."
		err "Veja o log: $LOG_BACKEND"
		return 2
		;;
	*)
		err "Backend nao respondeu em 5 minutos."
		err "Veja o log: $LOG_BACKEND"
		return 2
		;;
	esac

	# 4) No modo dev, espera o Vite responder
	if [ "$MODE" = "dev" ]; then
		say "[...] Aguardando http://localhost:${PORT_FRONTEND} responder 200 (ate 3 min)..."
		wait_http "http://localhost:${PORT_FRONTEND}/" 180 "$PID_FRONTEND"
		case $? in
		0) say "[OK] Frontend no ar! (http://localhost:${PORT_FRONTEND})" ;;
		2)
			err "O processo do frontend terminou antes de responder."
			err "Veja o log: $LOG_FRONTEND"
			return 2
			;;
		*)
			err "Frontend nao respondeu em 3 minutos."
			err "Veja o log: $LOG_FRONTEND"
			return 2
			;;
		esac
		url="http://localhost:${PORT_FRONTEND}"
	else
		url="http://localhost:${PORT_BACKEND}"
	fi

	# 5) Abre o navegador
	if open_browser "$url"; then
		say "[OK] Navegador aberto em $url"
	else
		say "[AVISO] Nao foi possivel abrir o navegador. Acesse manualmente: $url"
	fi

	say ""
	say "Servidores rodando em segundo plano."
	say "  Logs : $CACHE_DIR"
	say "  Parar: ./iniciar-doctum-rpa.sh --parar"
}

main() {
	local arg
	for arg in "$@"; do
		case "$arg" in
		-p | --producao | --production) MODE="prod" ;;
		-d | --dev) MODE="dev" ;;
		--parar | --stop) MODE="stop" ;;
		--status) MODE="status" ;;
		-h | --help) usage; exit 0 ;;
		*)
			err "Opcao desconhecida: $arg"
			usage
			exit 1
			;;
		esac
	done

	case "$MODE" in
	stop) do_stop ;;
	status) do_status ;;
	*) do_start ;;
	esac
}

main "$@"
