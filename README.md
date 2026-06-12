# Sistema de Gerenciamento de Inventário

- **Instituição:** PUCPR — Pontifícia Universidade Católica do Paraná
- **Disciplina:** Programação Lógica e Funcional
- **Professor:** Frank Alcantara
- **Aluno:** Guilherme Augusto Santiago Abib — [@guilhermeabib](https://github.com/guilhermeabib)

**Ambiente de execução online:** https://onlinegdb.com/2fzxyTg00

---

## Sobre o projeto

Sistema interativo de terminal escrito em Haskell para gerenciamento de estoque. O programa mantém um inventário de itens em memória, persiste o estado em disco a cada operação bem-sucedida e registra toda tentativa de operação em um log de auditoria append-only.

A arquitetura separa rigorosamente a lógica de negócio (funções puras) das operações de I/O, seguindo os princípios de programação funcional.

---

## Arquitetura

O código está organizado em quatro blocos dentro de `Main.hs`:

| Bloco | Conteúdo |
|-------|----------|
| 1 — Tipos de dados | `Item`, `Inventario`, `AcaoLog`, `StatusLog`, `LogEntry` — todos derivam `Show` e `Read` para serialização em disco |
| 2 — Funções puras | `addItem`, `removeItem`, `updateQty` — retornam `Either String ResultadoOperacao`, sem nenhuma operação de I/O |
| 3 — Análise de logs | `historicoPorItem`, `logsDeErro`, `itemMaisMovimentado`, `contagemPorAcao` |
| 4 — Camada de I/O | `main`, `loop`, `carregarInventario`, `carregarLogs`, `salvarInventario`, `registrarLog`, parser de comandos |

**Persistência:**
- Operação bem-sucedida (`Right`) — sobrescreve `Inventario.dat` com `writeFile` e acrescenta ao `Auditoria.log` com `appendFile`.
- Operação com falha (`Left`) — acrescenta apenas ao `Auditoria.log`; o estado permanece inalterado.

**Inicialização:** usa `catch` para tratar a ausência dos arquivos na primeira execução, iniciando com inventário e log vazios sem crashar.

---

## Como executar

### Localmente (recomendado)

Executar localmente é a forma completa de usar o sistema, pois permite ver a persistência real entre execuções — os arquivos `Inventario.dat` e `Auditoria.log` são criados e mantidos na pasta do projeto.

O programa usa apenas módulos da biblioteca padrão e não requer dependências externas.

```
ghc Main.hs -o inventario
.\inventario.exe        # Windows
./inventario            # Linux/Mac
```


### GDB Online — https://onlinegdb.com/2fzxyTg00

O link acima abre o projeto já carregado. Basta clicar em **Run** e interagir pelo console.

**Limitações importantes do GDB Online:**
- O sistema de arquivos é reinicializado a cada execução — `Inventario.dat` e `Auditoria.log` não persistem entre sessões.
- Não é possível demonstrar a persistência de estado entre execuções (Cenário 1).
- Dentro de uma mesma sessão, `writeFile`, `appendFile` e `readFile` funcionam normalmente — os demais comandos (`add`, `remove`, `update`, `report`, etc.) podem ser testados sem restrições.

---

## Comandos disponíveis

| Comando | Descrição |
|---------|-----------|
| `add <id> <nome> <quantidade> <categoria>` | Adiciona um item novo. Falha se o ID já existir ou a quantidade for zero. |
| `remove <id> <quantidade>` | Baixa unidades do estoque. Falha se o estoque for insuficiente. |
| `update <id> <quantidade>` | Redefine a quantidade absoluta de um item existente. |
| `buscar <id>` | Consulta um item. Consultas a IDs inexistentes são auditadas como `QueryFail`. |
| `list` | Lista todos os itens do inventário com quantidade e categoria. |
| `report` | Exibe relatório de auditoria: contagem por tipo de ação, logs de erro e item mais movimentado. |
| `seed` | Insere 10 itens de exemplo no inventário (ignora os que já existem). |
| `help` | Exibe a lista de comandos. |
| `exit` | Encerra o programa. |

`<nome>` e `<categoria>` devem ser uma única palavra, sem espaços.

---

## Cenários de teste (seção 4.1)

### Cenário 1 — Persistência de estado

Primeira execução sem arquivos de dados:

```
[Aviso] Inventario.dat ausente/ilegivel: iniciando vazio.
Inventario carregado: 0 item(ns).
inventario> [OK] Item TEC-001 (Teclado) adicionado: 10 un. [Perifericos]
inventario> [OK] Item MOU-002 (Mouse) adicionado: 25 un. [Perifericos]
inventario> [OK] Item MON-003 (Monitor) adicionado: 8 un. [Monitores]
```

Após encerrar com `exit`, os arquivos `Inventario.dat` e `Auditoria.log` são criados. Ao reiniciar e executar `list`:

```
Inventario carregado: 3 item(ns).
   - MON-003    | Monitor          | qtd: 8    | Monitores
   - MOU-002    | Mouse            | qtd: 25   | Perifericos
   - TEC-001    | Teclado          | qtd: 10   | Perifericos
Total de itens distintos: 3 | Unidades totais: 43
```

Os 3 itens foram carregados de `Inventario.dat`, comprovando a persistência entre execuções.

---

### Cenário 2 — Erro de lógica (estoque insuficiente)

```
inventario> [OK] Item TEC-001 (Teclado) adicionado: 10 un. [Perifericos]
inventario> [ERRO] Estoque insuficiente para 'TEC-001': em estoque 10, solicitado 15.
   - TEC-001    | Teclado          | qtd: 10   | Perifericos
```

- Mensagem de erro clara exibida no terminal.
- `Inventario.dat` permanece com 10 unidades (estado inalterado).
- `Auditoria.log` registrou a tentativa como falha:

```
LogEntry {timestamp = 2026-06-08 12:28:21 UTC, acao = Remove, detalhes = "remove TEC-001 15", status = Falha "Estoque insuficiente para 'TEC-001': em estoque 10, solicitado 15."}
```

---

### Cenário 3 — Relatório de erros

Após o Cenário 2, executando `report`:

```
============= RELATORIO DE AUDITORIA =============
Operacoes registradas no log: 2

-- Contagem por tipo de acao --
   Add       : 1
   Remove    : 1
   Update    : 0
   QueryFail : 0

-- Logs de erro (1) --
   [2026-06-08 12:28:21 UTC] Remove | remove TEC-001 15 | Falha: Estoque insuficiente para 'TEC-001': em estoque 10, solicitado 15.

-- Item mais movimentado (operacoes de sucesso) --
   TEC-001: 1 operacao(oes).
=================================================
```

A função `logsDeErro` exibe corretamente a falha registrada no Cenário 2.
