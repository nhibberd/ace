{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DoAndIfThenElse #-}
import           Ace.Data.Config
import           Ace.Data.Offline
import           Ace.Data.Protocol
import           Ace.Data.Robot
import           Ace.Data.Web
import           Ace.Serial
import qualified Ace.IO.Offline.Server as Server
import qualified Ace.Robot.Registry as Robot
import qualified Ace.Web as Web
import           Ace.World.Registry (Map(..))
import qualified Ace.World.Registry as World

import           Control.Concurrent.Async (mapConcurrently)

import           Data.Aeson (object, (.=), toJSON)
import qualified Data.List as List
import           Data.Maybe (fromJust)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.ByteString as ByteString

import           P

import           System.IO (IO)
import qualified System.IO as IO
import           System.Environment (getArgs, lookupEnv)
import           System.Exit (exitFailure)

import           X.Control.Monad.Trans.Either.Exit (orDie)

main :: IO ()
main = do
  gameCount <- lookupEnv "SIMULATION_GAMES"
  small <- setting "SIMULATION_SMALL" True False True
  medium <- setting "SIMULATION_MEDIUM" False False True
  large <- setting "SIMULATION_Large" False False True
  getArgs >>= \s ->
    case s of
      (_map:executable:_:_:_) -> do
        let
          bigint = maybe 10 id $ gameCount >>= readMaybe
          _runs = [1 .. bigint :: Int]
          ns = List.drop 2 s
          names = (\(a, b) -> RobotIdentifier (RobotName . Text.pack $ a) (Punter . Text.pack $ a <> b)) <$> List.zip ns (fmap show [0 :: Int ..])
        validateBots $ fmap identifierName names

        maps <- fmap join $ sequence [
--            World.pick $ Text.pack map
            if small then World.small else pure []
          , if medium then World.medium else pure []
          , if large then World.large else pure []
          ]

        g <- Web.generateNewId

        let
          zmaps = List.zip maps [0 :: Int ..]

        let
          morenames = List.permutations names

        results <- flip mapConcurrently zmaps $ \(map, i) -> do

--          x <- flip mapConcurrently runs $ \run -> do
          x <- forM (List.zip morenames [0 :: Int ..]) $ \(namex, run) -> do
            let
              gid = GameId $ gameId g <> Text.pack (show run) <> Text.pack (show i)
              config = List.head configs

            orDie Server.renderServerError $
              Server.run gid executable namex (mapWorld map) (ServerConfig config False)

          pure (map, x)

        IO.hPutStr IO.stdout . Text.unpack . Text.decodeUtf8 .
          render $ collectResults names results

      _ -> do
        IO.hPutStr IO.stderr "usage: server MAP EXECUTABLE BOT BOT ..."
        exitFailure

collectResults :: [RobotIdentifier] -> [(Map, [[PunterResult]])] -> [Result]
collectResults names maps = do
  robot <- names
  (map, games) <- maps
  let
    fredo = mconcat $ do
      game <- games
      let
        maxScore = List.head $ sortOn (Down . punterResultValue) game
        ownScore = fromJust $ find (\r -> identifierPunter robot == (identifierPunter . punterResultRobot) r) game
      if maxScore /= ownScore then
        [ResultDetail 1 0]
      else
        [ResultDetail 1 1]
  pure $ Result (identifierName robot) (identifierPunter robot) (mapName map) fredo

render :: [Result] -> ByteString.ByteString
render results =
  let
    percentage x = (fromIntegral (resultDetailWins . resultDetail $ x) / fromIntegral (resultDetailGames . resultDetail $ x)) * 100 :: Double
  in
    as toJSON . with (sortOn percentage results) $ \result ->
      object [
          "robot" .= (robotName . resultRobot) result
        , "punter" .= (renderPunter . resultPunter) result
        , "map" .= resultMap result
        , "games" .= (resultDetailGames . resultDetail) result
        , "wins" .= (resultDetailWins . resultDetail) result
        , "winss" .= percentage result
        ]

configs :: [Config]
configs = do
  futures <- [minBound .. maxBound]
  splurges <- [minBound .. maxBound]
  options <- [minBound .. maxBound]
  pure $ Config futures splurges options

validateBots :: [RobotName] -> IO ()
validateBots names = do
  let
    bots = catMaybes $ fmap Robot.pick names
  unless (length bots == length names) $ do
    IO.hPutStrLn IO.stderr $ "Couldn't find a match for all your requested bots [" <> (Text.unpack . Text.intercalate ", " $ robotName <$> names) <> "]. Available: "
    forM_ Robot.names $ \name ->
      IO.hPutStrLn IO.stderr $ "  " <> (Text.unpack . robotName) name
    exitFailure

setting :: [Char] -> a -> a -> a -> IO a
setting name dfault disabled enabled =
  with (lookupEnv name) $ \n -> case n of
    Nothing ->
      dfault
    Just "1" ->
      enabled
    Just "t" ->
      enabled
    Just "true" ->
      enabled
    Just "on" ->
      enabled
    _ ->
      disabled
