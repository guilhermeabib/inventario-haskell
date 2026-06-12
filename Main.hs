module Main where

import qualified Data.Map as Map
import Data.Map (Map)
import Data.Time (UTCTime, getCurrentTime)
import Data.List (foldl', isInfixOf, maximumBy)
import Data.Ord (comparing)
import Data.Char (toLower)
import Data.Maybe (mapMaybe)
import Text.Read (readMaybe)
import Control.Exception (catch, SomeException)
import System.IO (hSetBuffering, BufferMode(NoBuffering), stdout, hFlush, isEOF)


-- Bloco 1: Tipos de dados (todos derivam Show e Read para serialização em disco)

data Item = Item
  { itemID     :: String
  , nome       :: String
  , quantidade :: Int
  , categoria  :: String
  } deriving (Show, Read, Eq)

type Inventario = Map String Item

data AcaoLog = Add | Remove | Update | QueryFail
  deriving (Show, Read, Eq)

data StatusLog = Sucesso | Falha String
  deriving (Show, Read, Eq)

data LogEntry = LogEntry
  { timestamp :: UTCTime
  , acao      :: AcaoLog
  , detalhes  :: String
  , status    :: StatusLog
  } deriving (Show, Read)

type ResultadoOperacao = (Inventario, LogEntry)


-- Bloco 2: Funções puras (sem nenhuma operação de I/O)

addItem :: UTCTime -> String -> String -> Int -> String
        -> Inventario -> Either String ResultadoOperacao
addItem agora iid n qtd cat inv
  | qtd <= 0           = Left ("Quantidade invalida para '" ++ iid ++ "': deve ser maior que zero.")
  | Map.member iid inv = Left ("Item com ID '" ++ iid ++ "' ja existe. Use 'update' para alterar.")
  | otherwise =
      let novoItem = Item iid n qtd cat
          invNovo  = Map.insert iid novoItem inv
          det      = "Item " ++ iid ++ " (" ++ n ++ ") adicionado: " ++ show qtd ++ " un. [" ++ cat ++ "]"
          entry    = LogEntry agora Add det Sucesso
      in  Right (invNovo, entry)

removeItem :: UTCTime -> String -> Int
           -> Inventario -> Either String ResultadoOperacao
removeItem agora iid qtd inv
  | qtd <= 0  = Left ("Quantidade invalida para remover de '" ++ iid ++ "': deve ser maior que zero.")
  | otherwise =
      case Map.lookup iid inv of
        Nothing -> Left ("Item com ID '" ++ iid ++ "' nao encontrado.")
        Just it
          | quantidade it < qtd ->
              Left ("Estoque insuficiente para '" ++ iid
                    ++ "': em estoque " ++ show (quantidade it)
                    ++ ", solicitado " ++ show qtd ++ ".")
          | otherwise ->
              let novaQtd = quantidade it - qtd
                  itNovo  = it { quantidade = novaQtd }
                  invNovo = Map.insert iid itNovo inv
                  det     = "Removidas " ++ show qtd ++ " un. de " ++ iid
                            ++ " (" ++ nome it ++ "). Restam " ++ show novaQtd ++ " un."
                  entry   = LogEntry agora Remove det Sucesso
              in  Right (invNovo, entry)

updateQty :: UTCTime -> String -> Int
          -> Inventario -> Either String ResultadoOperacao
updateQty agora iid novaQtd inv
  | novaQtd < 0 = Left ("Quantidade invalida para '" ++ iid ++ "': nao pode ser negativa.")
  | otherwise =
      case Map.lookup iid inv of
        Nothing -> Left ("Item com ID '" ++ iid ++ "' nao encontrado.")
        Just it ->
          let itNovo  = it { quantidade = novaQtd }
              invNovo = Map.insert iid itNovo inv
              det     = "Quantidade de " ++ iid ++ " (" ++ nome it
                        ++ ") atualizada de " ++ show (quantidade it)
                        ++ " para " ++ show novaQtd ++ " un."
              entry   = LogEntry agora Update det Sucesso
          in  Right (invNovo, entry)


-- Bloco 3: Análise de logs (funções puras de relatório)

historicoPorItem :: String -> [LogEntry] -> [LogEntry]
historicoPorItem iid = filter (\e -> iid `isInfixOf` detalhes e)

logsDeErro :: [LogEntry] -> [LogEntry]
logsDeErro = filter ehFalha
  where
    ehFalha e = case status e of
                  Falha _ -> True
                  Sucesso -> False

contagemPorAcao :: [LogEntry] -> [(AcaoLog, Int)]
contagemPorAcao logs =
  [ (a, length (filter ((== a) . acao) logs))
  | a <- [Add, Remove, Update, QueryFail] ]

itemMaisMovimentado :: [String] -> [LogEntry] -> Maybe (String, Int)
itemMaisMovimentado ids logs
  | null candidatos = Nothing
  | otherwise       = Just (maximumBy (comparing snd) candidatos)
  where
    sucessos   = filter ((== Sucesso) . status) logs
    contagem i = length (historicoPorItem i sucessos)
    candidatos = filter ((> 0) . snd) [ (i, contagem i) | i <- ids ]


-- Bloco 4: Camada de I/O (main, loop, persistência, parser)

arquivoInventario :: FilePath
arquivoInventario = "Inventario.dat"

arquivoLog :: FilePath
arquivoLog = "Auditoria.log"

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  imprimirCabecalho
  inv  <- carregarInventario
  logs <- carregarLogs
  putStrLn ("Inventario carregado: " ++ show (Map.size inv) ++ " item(ns).")
  putStrLn ("Log de auditoria carregado: " ++ show (length logs) ++ " registro(s).")
  putStrLn "Digite 'help' para ver os comandos disponiveis."
  loop inv

-- Retorna string vazia em caso de falha de I/O (arquivo inexistente, etc.)
semArquivo :: SomeException -> IO String
semArquivo _ = return ""

carregarInventario :: IO Inventario
carregarInventario = do
  conteudo <- readFile arquivoInventario `catch` semArquivo
  case readMaybe conteudo of
    Just inv -> return inv
    Nothing  -> do
      putStrLn "[Aviso] Inventario.dat ausente/ilegivel: iniciando vazio."
      return Map.empty

carregarLogs :: IO [LogEntry]
carregarLogs = do
  conteudo <- readFile arquivoLog `catch` semArquivo
  return (mapMaybe readMaybe (lines conteudo))

salvarInventario :: Inventario -> IO ()
salvarInventario inv = writeFile arquivoInventario (show inv)

registrarLog :: LogEntry -> IO ()
registrarLog entry = appendFile arquivoLog (show entry ++ "\n")

loop :: Inventario -> IO ()
loop inv = do
  putStr "\ninventario> "
  hFlush stdout
  fim <- isEOF
  if fim
    then putStrLn "\n[Encerrado] Fim da entrada. Estado e log salvos em disco."
    else do
      entrada <- getLine
      case words entrada of
        []       -> loop inv
        (c:args) -> processar (map toLower c) args inv

processar :: String -> [String] -> Inventario -> IO ()
processar cmd args inv = case cmd of
  "add"       -> cmdAdd args inv
  "remove"    -> cmdRemove args inv
  "update"    -> cmdUpdate args inv
  "buscar"    -> cmdBuscar args inv
  "list"      -> cmdList inv   >> loop inv
  "listar"    -> cmdList inv   >> loop inv
  "report"    -> cmdReport inv >> loop inv
  "relatorio" -> cmdReport inv >> loop inv
  "seed"      -> cmdSeed inv
  "popular"   -> cmdSeed inv
  "help"      -> imprimirAjuda >> loop inv
  "ajuda"     -> imprimirAjuda >> loop inv
  "exit"      -> sair
  "sair"      -> sair
  "quit"      -> sair
  _           -> do
      putStrLn ("Comando desconhecido: '" ++ cmd ++ "'. Digite 'help'.")
      loop inv

-- Aplica o resultado de uma operação pura: persiste se Right, só audita se Left
aplicar :: UTCTime -> AcaoLog -> String
        -> Either String ResultadoOperacao -> Inventario -> IO ()
aplicar agora ac tentativa resultado inv = case resultado of
  Right (invNovo, entry) -> do
    salvarInventario invNovo
    registrarLog entry
    putStrLn ("[OK] " ++ detalhes entry)
    loop invNovo
  Left erro -> do
    let entry = LogEntry agora ac tentativa (Falha erro)
    registrarLog entry
    putStrLn ("[ERRO] " ++ erro)
    loop inv

cmdAdd :: [String] -> Inventario -> IO ()
cmdAdd args inv = case args of
  [iid, n, qStr, cat] ->
    case readMaybe qStr :: Maybe Int of
      Nothing -> putStrLn "Quantidade invalida: informe um inteiro." >> loop inv
      Just q  -> do
        agora <- getCurrentTime
        aplicar agora Add ("add " ++ unwords args) (addItem agora iid n q cat inv) inv
  _ -> putStrLn "Uso: add <id> <nome> <quantidade> <categoria>" >> loop inv

cmdRemove :: [String] -> Inventario -> IO ()
cmdRemove args inv = case args of
  [iid, qStr] ->
    case readMaybe qStr :: Maybe Int of
      Nothing -> putStrLn "Quantidade invalida: informe um inteiro." >> loop inv
      Just q  -> do
        agora <- getCurrentTime
        aplicar agora Remove ("remove " ++ unwords args) (removeItem agora iid q inv) inv
  _ -> putStrLn "Uso: remove <id> <quantidade>" >> loop inv

cmdUpdate :: [String] -> Inventario -> IO ()
cmdUpdate args inv = case args of
  [iid, qStr] ->
    case readMaybe qStr :: Maybe Int of
      Nothing -> putStrLn "Quantidade invalida: informe um inteiro." >> loop inv
      Just q  -> do
        agora <- getCurrentTime
        aplicar agora Update ("update " ++ unwords args) (updateQty agora iid q inv) inv
  _ -> putStrLn "Uso: update <id> <nova_quantidade>" >> loop inv

cmdBuscar :: [String] -> Inventario -> IO ()
cmdBuscar args inv = case args of
  [iid] -> case Map.lookup iid inv of
    Just it -> do
      putStrLn "Item encontrado:"
      imprimirItem it
      loop inv
    Nothing -> do
      agora <- getCurrentTime
      let det   = "Consulta ao item " ++ iid
          entry = LogEntry agora QueryFail det (Falha ("Item '" ++ iid ++ "' nao encontrado."))
      registrarLog entry
      putStrLn ("[ERRO] Item '" ++ iid ++ "' nao encontrado.")
      loop inv
  _ -> putStrLn "Uso: buscar <id>" >> loop inv

cmdList :: Inventario -> IO ()
cmdList inv
  | Map.null inv =
      putStrLn "Inventario vazio. Use 'seed' para popular ou 'add' para inserir."
  | otherwise = do
      putStrLn "================== INVENTARIO ===================="
      mapM_ imprimirItem (Map.elems inv)
      putStrLn ("Total de itens distintos: " ++ show (Map.size inv)
                ++ " | Unidades totais: "
                ++ show (sum (map quantidade (Map.elems inv))))
      putStrLn "================================================="

cmdReport :: Inventario -> IO ()
cmdReport inv = do
  logs <- carregarLogs
  putStrLn ""
  putStrLn "============= RELATORIO DE AUDITORIA ============="
  putStrLn ("Operacoes registradas no log: " ++ show (length logs))
  putStrLn ""
  putStrLn "-- Contagem por tipo de acao --"
  mapM_ (\(a, c) -> putStrLn ("   " ++ pad 10 (show a) ++ ": " ++ show c))
        (contagemPorAcao logs)
  let erros = logsDeErro logs
  putStrLn ""
  putStrLn ("-- Logs de erro (" ++ show (length erros) ++ ") --")
  if null erros
    then putStrLn "   Nenhum erro registrado."
    else mapM_ (putStrLn . formatLog) erros
  putStrLn ""
  putStrLn "-- Item mais movimentado (operacoes de sucesso) --"
  case itemMaisMovimentado (Map.keys inv) logs of
    Nothing     -> putStrLn "   Nenhuma movimentacao de sucesso registrada."
    Just (i, c) -> putStrLn ("   " ++ i ++ ": " ++ show c ++ " operacao(oes).")
  putStrLn "================================================="

cmdSeed :: Inventario -> IO ()
cmdSeed inv = do
  agora <- getCurrentTime
  let (invNovo, novos) = semearPuro agora inv
  if null novos
    then putStrLn "Itens de exemplo ja presentes. Nada a fazer." >> loop inv
    else do
      salvarInventario invNovo
      mapM_ registrarLog novos
      putStrLn ("Inseridos " ++ show (length novos) ++ " item(ns) de exemplo no inventario.")
      loop invNovo

semearPuro :: UTCTime -> Inventario -> (Inventario, [LogEntry])
semearPuro agora inv0 = foldl' passo (inv0, []) itensExemplo
  where
    passo (inv, es) (i, n, q, c) =
      case addItem agora i n q c inv of
        Right (inv', e) -> (inv', es ++ [e])
        Left _          -> (inv, es)

itensExemplo :: [(String, String, Int, String)]
itensExemplo =
  [ ("TEC-001", "Teclado",       10, "Perifericos")
  , ("MOU-002", "Mouse",         25, "Perifericos")
  , ("MON-003", "Monitor",        8, "Monitores")
  , ("NOT-004", "Notebook",       5, "Computadores")
  , ("SSD-005", "SSD480GB",      30, "Armazenamento")
  , ("HD-006",  "HD1TB",         15, "Armazenamento")
  , ("RAM-007", "Memoria8GB",    40, "Componentes")
  , ("CPU-008", "ProcessadorI5", 12, "Componentes")
  , ("GPU-009", "PlacaVideoRTX",  6, "Componentes")
  , ("FON-010", "Fonte650W",     20, "Componentes")
  ]

imprimirItem :: Item -> IO ()
imprimirItem it =
  putStrLn ("   - " ++ pad 10 (itemID it) ++ " | " ++ pad 16 (nome it)
            ++ " | qtd: " ++ pad 4 (show (quantidade it))
            ++ " | " ++ categoria it)

formatLog :: LogEntry -> String
formatLog e =
  "   [" ++ show (timestamp e) ++ "] " ++ pad 10 (show (acao e))
  ++ " | " ++ detalhes e ++ " | " ++ statusStr (status e)
  where
    statusStr Sucesso     = "Sucesso"
    statusStr (Falha msg) = "Falha: " ++ msg

pad :: Int -> String -> String
pad n s = s ++ replicate (max 0 (n - length s)) ' '

imprimirCabecalho :: IO ()
imprimirCabecalho = do
  putStrLn "================================================="
  putStrLn "   SISTEMA DE GERENCIAMENTO DE INVENTARIO"
  putStrLn "   Programacao Logica e Funcional - Haskell"
  putStrLn "================================================="

imprimirAjuda :: IO ()
imprimirAjuda = mapM_ putStrLn
  [ "Comandos disponiveis:"
  , "  add <id> <nome> <quantidade> <categoria>  - adiciona um item novo"
  , "  remove <id> <quantidade>                  - baixa do estoque"
  , "  update <id> <nova_quantidade>             - redefine a quantidade"
  , "  buscar <id>                               - consulta um item"
  , "  list   (ou listar)                        - lista o inventario"
  , "  report (ou relatorio)                     - relatorio de auditoria"
  , "  seed   (ou popular)                       - insere 10 itens de exemplo"
  , "  help   (ou ajuda)                         - mostra esta ajuda"
  , "  exit   (ou sair/quit)                     - encerra o programa"
  , ""
  , "Observacao: <nome> e <categoria> devem ser uma unica palavra"
  , "            (sem espacos). Ex.: add SSD-011 SSD1TB 12 Armazenamento"
  ]

sair :: IO ()
sair = putStrLn "Encerrando. Estado e log ja persistidos em disco. Ate logo!"
