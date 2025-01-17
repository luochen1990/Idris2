module Main

import Core.Binary
import Core.Context
import Core.Core
import Core.Directory
import Core.InitPrimitives
import Core.Metadata
import Core.Options
import Core.Unify

import Idris.CommandLine
import Idris.Desugar
import Idris.IDEMode.REPL
import Idris.ModTree
import Idris.Package
import Idris.Parser
import Idris.ProcessIdr
import Idris.REPL
import Idris.SetOptions
import Idris.Syntax

import Idris.Socket
import Idris.Socket.Data

import Data.Vect
import System

import Yaffle.Main
import YafflePaths

%default covering

findInput : List CLOpt -> Maybe String
findInput [] = Nothing
findInput (InputFile f :: fs) = Just f
findInput (_ :: fs) = findInput fs

-- Add extra library directories from the "BLODWEN_PATH"
-- environment variable
updatePaths : {auto c : Ref Ctxt Defs} ->
              Core ()
updatePaths
    = do setPrefix yprefix
         defs <- get Ctxt
         bpath <- coreLift $ getEnv "IDRIS2_PATH"
         case bpath of
              Just path => do traverse addExtraDir (map trim (split (==pathSep) path))
                              pure ()
              Nothing => pure ()
         bdata <- coreLift $ getEnv "IDRIS2_DATA"
         case bdata of
              Just path => do traverse addDataDir (map trim (split (==pathSep) path))
                              pure ()
              Nothing => pure ()
         blibs <- coreLift $ getEnv "IDRIS2_LIBS"
         case blibs of
              Just path => do traverse addLibDir (map trim (split (==pathSep) path))
                              pure ()
              Nothing => pure ()
         -- IDRIS2_PATH goes first so that it overrides this if there's
         -- any conflicts. In particular, that means that setting IDRIS2_PATH
         -- for the tests means they test the local version not the installed
         -- version
         addPkgDir "prelude"
         addPkgDir "base"
         addDataDir (dir_prefix (dirs (options defs)) ++ dirSep ++
                        "idris2-" ++ version ++ dirSep ++ "support")
         addLibDir (dir_prefix (dirs (options defs)) ++ dirSep ++
                        "idris2-" ++ version ++ dirSep ++ "lib")

updateREPLOpts : {auto o : Ref ROpts REPLOpts} ->
                 Core ()
updateREPLOpts
    = do opts <- get ROpts
         ed <- coreLift $ getEnv "EDITOR"
         case ed of
              Just e => put ROpts (record { editor = e } opts)
              Nothing => pure ()

showInfo : {auto c : Ref Ctxt Defs}
        -> {auto o : Ref ROpts REPLOpts}
        -> List CLOpt
        -> Core Bool
showInfo Nil = pure False
showInfo (BlodwenPaths :: _)
    = do defs <- get Ctxt
         iputStrLn (toString (dirs (options defs)))
         pure True
showInfo (_::rest) = showInfo rest

tryYaffle : List CLOpt -> Core Bool
tryYaffle [] = pure False
tryYaffle (Yaffle f :: _) = do yaffleMain f []
                               pure True
tryYaffle (c :: cs) = tryYaffle cs

stMain : List CLOpt -> Core ()
stMain opts
    = do False <- tryYaffle opts
            | True => pure ()
         defs <- initDefs
         c <- newRef Ctxt defs
         s <- newRef Syn initSyntax
         m <- newRef MD initMetadata
         addPrimitives

         setWorkingDir "."
         updatePaths
         let ide = ideMode opts
         let ideSocket = ideModeSocket opts
         let outmode = if ide then IDEMode 0 stdin stdout else REPL False
         let fname = findInput opts
         o <- newRef ROpts (REPLOpts.defaultOpts fname outmode)

         finish <- showInfo opts
         if finish
         then pure ()
         else do

           -- If there's a --build or --install, just do that then quit
           done <- processPackageOpts opts

           when (not done) $
              do True <- preOptions opts
                     | False => pure ()

                 u <- newRef UST initUState
                 updateREPLOpts
                 session <- getSession
                 case fname of
                      Nothing => logTime "Loading prelude" $
                                   when (not $ noprelude session) $
                                     readPrelude
                      Just f => logTime "Loading main file" $
                                   loadMainFile f

                 doRepl <- postOptions opts
                 if doRepl
                 then
                   if ide || ideSocket
                   then
                     if not ideSocket
                     then do
                       setOutput (IDEMode 0 stdin stdout)
                       replIDE {c} {u} {m}
                     else do
                       let (host, port) = ideSocketModeHostPort opts
                       f <- coreLift $ initIDESocketFile host port
                       case f of
                         Left err => do
                           coreLift $ putStrLn err
                           coreLift $ exit 1
                         Right file => do
                           setOutput (IDEMode 0 file file)
                           replIDE {c} {u} {m}
                   else do
                       iputStrLn $ "Welcome to Idris 2 version " ++ version
                                    ++ ". Enjoy yourself!"
                       repl {c} {u} {m}
                 else
                      -- exit with an error code if there was an error, otherwise
                      -- just exit
                    do ropts <- get ROpts
                       case errorLine ropts of
                         Nothing => pure ()
                         Just _ => coreLift $ exit 1

-- Run any options (such as --version or --help) which imply printing a
-- message then exiting. Returns wheter the program should continue
quitOpts : List CLOpt -> IO Bool
quitOpts [] = pure True
quitOpts (Version :: _)
    = do putStrLn versionMsg
         pure False
quitOpts (Help :: _)
    = do putStrLn usage
         pure False
quitOpts (ShowPrefix :: _)
    = do putStrLn yprefix
         pure False
quitOpts (_ :: opts) = quitOpts opts

main : IO ()
main = do Right opts <- getCmdOpts
             | Left err =>
                    do putStrLn err
                       putStrLn usage
          continue <- quitOpts opts
          if continue
             then
                coreRun (stMain opts)
                     (\err : Error =>
                             do putStrLn ("Uncaught error: " ++ show err)
                                exit 1)
                     (\res => pure ())
             else pure ()
