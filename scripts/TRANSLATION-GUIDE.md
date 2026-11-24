# Guia de Tradução – Doctum RPA

Este guia explica como adicionar e manter traduções no Doctum RPA (fork do n8n).

## Visão Geral

O sistema de internacionalização (i18n) usa **vue-i18n** com arquivos JSON de chave-valor plano. Existem **3 camadas de tradução** independentes:

| Camada | Descrição | Caminho | Formato |
|--------|-----------|---------|---------|
| **main** | Interface principal do n8n | `packages/frontend/@n8n/i18n/src/locales/` | JSON (~10.200 chaves) |
| **design** | Design system (componentes reutilizáveis) | `packages/frontend/@n8n/design-system/src/locale/lang/` | TypeScript (~300 chaves) |
| **mcp** | MCP Apps | `packages/@n8n/mcp-apps/src/locales/` | JSON (~15 chaves) |

## Adicionando um Novo Locale

### 1. Criar os arquivos de tradução

```bash
# Camada principal (main)
cp packages/frontend/@n8n/i18n/src/locales/en.json \
   packages/frontend/@n8n/i18n/src/locales/pt.json

# Camada MCP
cp packages/@n8n/mcp-apps/src/locales/en.json \
   packages/@n8n/mcp-apps/src/locales/pt.json

# Camada design system – copie o en.ts e renomeie
cp packages/frontend/@n8n/design-system/src/locale/lang/en.ts \
   packages/frontend/@n8n/design-system/src/locale/lang/pt.ts
```

### 2. Configurar o locale padrão

Defina a variável de ambiente antes de iniciar o n8n:

```bash
export N8N_DEFAULT_LOCALE=pt
```

Ou adicione ao arquivo `.env` na raiz do projeto:

```
N8N_DEFAULT_LOCALE=pt
```

### 3. Traduzir as chaves

O formato dos arquivos JSON é plano (flat):

```json
{
  "settings.title": "Configurações",
  "settings.save": "Salvar",
  "nodeView.runButton.tooltip": "Executar workflow | Ctrl+Enter"
}
```

**Regras importantes:**

- **Variáveis de interpolação** como `{name}`, `{count}`, `{total}` devem ser mantidas exatamente como estão
- **Plurais com pipe** usam o formato `"singular | plural"` — mantenha o mesmo número de segmentos
- **HTML inline** (ex: `<b>`, `<a>`) deve ser preservado
- **Não traduza** nomes de marca, URLs, ou identificadores técnicos

### 4. Usar o script auxiliar

```bash
# Ver progresso geral
python3 scripts/translate-helper.py status --locale pt

# Listar chaves faltando
python3 scripts/translate-helper.py missing --locale pt

# Exportar chaves faltantes para tradução em lote
python3 scripts/translate-helper.py export-missing --locale pt
# Gera: scripts/missing-main-pt.json, scripts/missing-mcp-pt.json

# Verificar problemas de formatação
python3 scripts/translate-helper.py validate --locale pt

# Focar em uma camada específica
python3 scripts/translate-helper.py diff --locale pt --layer main
```

## Fluxo de Trabalho Recomendado

1. **Exporte** as chaves faltantes com `export-missing`
2. **Traduza** o arquivo JSON exportado (pode usar ferramentas de tradução assistida)
3. **Copie** as traduções para o arquivo de locale correspondente
4. **Valide** com o comando `validate` para garantir que variáveis e plurais estão corretos
5. **Teste** a interface com `N8N_DEFAULT_LOCALE=pt`

## Traduções de Nodes e Credenciais

Além das 3 camadas de interface, nodes e credenciais têm seu próprio sistema de tradução:

### Estrutura

```
packages/nodes-base/
  nodes/
    NomeDoNode/
      translations/
        pt/
          nomeDoNode.json
  credentials/
    translations/
      pt/
        nomeDaCredencial.json
```

### Formato dos arquivos de node

```json
{
  "header": {
    "displayName": "Nome do Node em Português"
  },
  "description": "Descrição do node",
  "properties": {
    "operation": {
      "displayName": "Operação",
      "options": {
        "create": {
          "displayName": "Criar",
          "description": "Cria um novo registro"
        }
      }
    }
  }
}
```

### Como adicionar

1. Crie o diretório `translations/pt/` dentro do node desejado
2. Crie o arquivo JSON com a mesma estrutura do node
3. O n8n carrega automaticamente as traduções ao detectar o locale

> **Nota:** A tradução de nodes é opcional e incremental. Nodes sem tradução usam o texto em inglês.

## Referência dos Comandos

| Comando | Descrição |
|---------|-----------|
| `status` | Mostra barra de progresso por locale |
| `diff` | Mostra chaves em `en` que faltam no locale alvo |
| `missing` | Lista todas as chaves não traduzidas (ausentes + vazias) |
| `export-missing` | Exporta chaves faltantes para JSON separado |
| `validate` | Verifica variáveis de interpolação, plurais e valores vazios |

### Opções

| Flag | Padrão | Descrição |
|------|--------|-----------|
| `--locale` | `pt` | Código do locale (ex: `pt`, `es`, `fr`) |
| `--layer` | todas | Camada: `main`, `design`, ou `mcp` |

## Dicas

- Comece traduzindo as chaves mais visíveis: `nodeView.*`, `settings.*`, `generic.*`
- Use `validate` frequentemente para pegar erros de interpolação cedo
- O design system (camada `design`) contém textos de componentes comuns — traduzir essa camada tem impacto visual grande
- Para a camada `design`, edite o arquivo `.ts` diretamente, mantendo a sintaxe TypeScript
- Valores que são funções arrow (`(config) => ...`) precisam ser adaptados manualmente
