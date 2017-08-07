{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

import           Ace.Data.Config
import           Ace.Data.Robot
import           Ace.Data.Web
import qualified Ace.IO.Offline.Server as Server
import qualified Ace.Robot.Registry as Robot
import qualified Ace.Web as Web
import qualified Ace.World.Registry as World

import qualified Data.List as List
import qualified Data.Text as Text

import           P

import           System.IO (IO)
import qualified System.IO as IO
import           System.Environment (getArgs)
import           System.Exit (exitFailure)

import           X.Control.Monad.Trans.Either.Exit (orDie)

main :: IO ()
main =
  getArgs >>= \s ->
    case s of
      (map:executable:_:_:_) -> do
        let
          runs = [0 .. 10 :: Int]
          names = (RobotName . Text.pack) <$> List.drop 2 s
        validateBots names

        world <- World.pick $ Text.pack map

        g <- Web.generateNewId
        IO.hPutStrLn IO.stderr . Text.unpack $ "Game prefix: " <> (gameId g)
        forM_ runs $ \run -> do
          let
            gid = GameId $ gameId g <> Text.pack (show run)
            config = List.head configs

          orDie Server.renderServerError $
            Server.run gid executable names world config

      _ -> do
        IO.hPutStr IO.stderr "usage: server MAP EXECUTABLE BOT BOT ..."
        exitFailure


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
