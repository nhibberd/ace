{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE OverloadedStrings #-}
module Ace.Robot.Silver (
    silver
  ) where

import           Ace.Data
import           Ace.Score
import qualified Ace.Serial as Serial

import qualified Data.Graph.Inductive.Basic as Graph
import qualified Data.Graph.Inductive.Graph as Graph
import           Data.Graph.Inductive.PatriciaTree (Gr)
import qualified Data.Graph.Inductive.Query.SP as Graph
import           Data.Maybe (isJust)
import qualified Data.Vector.Unboxed as Unboxed

import           P

import           System.IO (IO)


silver :: Robot [Move]
silver =
  Robot "silver" init move Serial.fromMoves Serial.toMoves

init :: Setup -> IO (Initialisation [Move])
init _ =
  pure $ Initialisation [] []

scorePath :: Graph.Path -> Gr SiteId (Maybe PunterId) -> Int
scorePath nodes graph0 =
  let
    graph =
      Graph.elfilter (not . isJust) graph0
  in
    sum . with nodes $ \node ->
      case fst $ Graph.match node graph of
        Nothing ->
          1
        Just ((_, _) : _, _, _, _) ->
          0
        Just _ ->
          1

fromPath :: Graph.Path -> Gr SiteId (Maybe PunterId) -> Maybe River
fromPath nodes graph0 =
  let
    graph =
      Graph.elfilter (not . isJust) graph0
  in
    head . flip mapMaybe nodes $ \node ->
      case fst $ Graph.match node graph of
        Nothing ->
          Nothing
        Just ((_, other) : _, _, _, _) ->
          Just $ makeRiver (SiteId node) (SiteId other)
        Just _ ->
          Nothing

move :: Gameplay -> State [Move] -> IO (RobotMove [Move])
move g s =
  let
    pid =
      statePunter s

    mines =
      Unboxed.toList . worldMines $ stateWorld s

    previousMoves =
      gameplay g <> stateData s

    graph0 =
      Graph.elfilter (\x -> x == Just pid || x == Nothing) .
      assignRivers previousMoves .
      fromWorld $
      stateWorld s

    graph =
      Graph.emap (const (1 :: Int)) graph0

    fromTuple (n, m, x) =
      fmap (n, m,) $ fromPath x graph0

    fromPaths xs =
      case xs of
        [] ->
          pure $ RobotPass previousMoves

        (_, _, x) : _ ->
          pure $ RobotClaim previousMoves x
  in
    fromPaths .
    mapMaybe fromTuple .
    sortOn (\(x, y, _) -> Down (x, y)) .
    concat .
    with mines $ \mid ->
    with (Graph.nodes graph) $ \node ->
      let
        path =
          Graph.sp (siteId mid) node graph

        distance =
          case path of
            [] ->
              0
            xs ->
              length xs - 1
      in
        (distance * distance, scorePath path graph0, path)
