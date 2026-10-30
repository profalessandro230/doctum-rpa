# Guia de Instalação — Doctum RPA

Passo a passo completo para instalar e rodar o **Doctum RPA** (fork personalizado do n8n) **com** e **sem Docker**, para **Linux** e **Windows**.

Para a lista de versões exatas das ferramentas, veja o [`requirements.txt`](../requirements.txt).

---

## Sumário

- [Pré-requisitos](#pré-requisitos)
- [Opção A — Com Docker](#opção-a--com-docker)
- [Opção B — Sem Docker (nativo)](#opção-b--sem-docker-nativo)
- [Primeiro acesso e criação do usuário](#primeiro-acesso-e-criação-do-usuário)
- [Comandos úteis](#comandos-úteis)
- [Solução de problemas](#solução-de-problemas)

---

## Pré-requisitos

| Ferramenta | Versão mínima | Verificar com | Linux (instalar) | Windows (instalar) |
|---|---|---|---|---|
| Node.js | ≥ 24.0.0 | `node --version` | nodesource setup_24.x | nodejs.org |
| pnpm | ≥ 12.4.2 | `pnpm --version` | `corepack enable` | `corepack enable` |
| Git | ≥ 2.35 | `git --version` | `apt install git` | git-scm.com |
| Docker (só Opção A) | ≥ 24.x | `docker --version` | get.docker.com | Docker Desktop |

---

## Opção A — Com Docker

Recomendado para quem quer subir a instância rápido, sem compilar.

### Linux (Ubuntu / Debian)

```bash
# 1. Instalar o Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Faça logout e login novamente para o grupo ter efeito
docker --version

# 2. Criar volume para persistir dados (~/.n8n)
docker volume create n8n_data

# 3. Subir o container
docker run -d \
  --name doctum-n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e GENERIC_TIMEZONE="America/Sao_Paulo" \
  -e TZ="America/Sao_Paulo" \
  docker.n8n.io/n8nio/n8n:2.45.0

# 4. Ver logs (opcional)
docker logs -f doctum-n8n

# 5. Acessar
# http://localhost:5678
```

### Windows (PowerShell + Docker Desktop)

```powershell
# 1. Instalar o Docker Desktop: https://www.docker.com/products/docker-desktop/
#    Inicie o Docker Desktop e aguarde o ícone verde na bandeja.
docker --version

# 2. Criar volume
docker volume create n8n_data

# 3. Subir o container
docker run -d `
  --name doctum-n8n `
  --restart unless-stopped `
  -p 5678:5678 `
  -v n8n_data:/home/node/.n8n `
  -e GENERIC_TIMEZONE="America/Sao_Paulo" `
  -e TZ="America/Sao_Paulo" `
  docker.n8n.io/n8nio/n8n:2.45.0

# 4. Acessar
# http://localhost:5678
```

### Construindo a imagem personalizada Doctum (a partir do código)

A imagem oficial `docker.n8n.io/n8nio/n8n` roda o n8n padrão. Para a interface Doctum (paleta azul, layout vertical, logo), construa a partir deste repositório:

```bash
# Na raiz do repositório
docker build -t doctum-rpa:latest .

docker run -d \
  --name doctum-n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e TZ="America/Sao_Paulo" \
  doctum-rpa:latest
```

### Parar / remover

```bash
docker stop doctum-n8n       # parar
docker start doctum-n8n      # religar
docker rm -f doctum-n8n      # remover (o volume n8n_data preserva os dados)
```

---

## Opção B — Sem Docker (nativo)

Recomendado para desenvolvimento e para ver/alterar o código personalizado.

### Linux (Ubuntu / Debian)

```bash
# 1. Pré-requisitos
sudo apt update
sudo apt install -y git curl

# Node.js 24 (via NodeSource)
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
node --version   # >= 24

# 2. pnpm via corepack (já vem com o Node)
corepack enable
corepack prepare pnpm@12.4.2 --activate
pnpm --version   # >= 12.4.2

# 3. Clonar
git clone https://github.com/<SEU_USUARIO>/doctum-rpa.git
cd doctum-rpa

# 4. Instalar dependências do monorepo
pnpm install --frozen-lockfile

# 5. Compilar os pacotes
pnpm build

# 6. Iniciar
pnpm n8n

# 7. Acessar http://localhost:5678 e criar o usuário
```

### Windows (PowerShell)

```powershell
# 1. Instalar Node.js 24+: https://nodejs.org
#    Instalar Git: https://git-scm.com/download/win
node --version
git --version

# 2. pnpm via corepack
corepack enable
corepack prepare pnpm@12.4.2 --activate
pnpm --version

# 3. Clonar (prefira um caminho curto e SEM espaços)
git clone https://github.com/<SEU_USUARIO>/doctum-rpa.git
cd doctum-rpa

# 4. Instalar dependências
pnpm install --frozen-lockfile

# 5. Compilar
pnpm build

# 6. Iniciar
pnpm n8n

# 7. Acessar http://localhost:5678
```

> **Dica Windows — espaços no caminho:** se o projeto estiver em uma pasta com espaços (ex.: `C:\Users\Meu Usuario\Documents\Meu Projeto`), o n8n pode falhar. Crie uma letra de unidade:
>
> ```powershell
> subst W: "C:\Users\Meu Usuario\Documents\doctum-rpa"
> W:
> ```

### Iniciar somente o frontend (desenvolvimento da interface)

```bash
# Terminal 1 — backend
pnpm n8n

# Terminal 2 — frontend em modo dev (Vite, porta 8080)
pnpm --filter n8n-editor-ui dev
```

---

## Primeiro acesso e criação do usuário

1. Abra `http://localhost:5678`.
2. A tela de setup pede para criar o **owner** (primeiro usuário).
3. Informe **e-mail**, **nome** e **senha** e conclua o setup.
4. Faça login com essas credenciais.

> Neste ambiente de estudo, o usuário owner já foi configurado. Para redefinir, apague `~/.n8n/database.sqlite` (perde os dados) ou use `n8n user-management:reset`.

---

## Comandos úteis

```bash
pnpm n8n start            # iniciar o servidor
pnpm n8n --version        # versão do n8n
pnpm n8n user-management:reset   # resetar owner (cuidado: pede re-setup)

# Testes (Vitest)
pnpm vitest run <caminho>          # rodar um arquivo de teste
pnpm vitest run <caminho> -u       # atualizar snapshots

# Docker
docker logs -f doctum-n8n          # acompanhar logs
docker exec -it doctum-n8n sh      # shell dentro do container
```

---

## Solução de problemas

| Problema | Causa provável | Solução |
|---|---|---|
| `ENOENT` / falha ao iniciar com caminho com espaços | Pasta do projeto contém espaços | Use `subst` ou mova para caminho curto |
| `EADDRINUSE` na porta 5678 | Outra instância rodando | Mude a porta (`N8N_PORT=5679`) ou mate o processo |
| `task runner` erro 403 | Token de permissão | Não crítico; desabilite ou configure `N8N_RUNNERS_ENABLED` |
| Build lento / memória alta | Monorepo grande | Feche outros programas; use `pnpm build` incremental |
| Docker sem permissão (Linux) | Usuário fora do grupo `docker` | `sudo usermod -aG docker $USER` e relogue |
| Frontend não carrega no dev | Vite ainda compilando | Aguarde ~60s no primeiro acesso |

---

## Próximos passos

Após instalar, siga o [guia "Olá Mundo"](README.md#guia-de-uso--primeiro-workflow-olá-mundo) no README principal para criar seu primeiro workflow.
