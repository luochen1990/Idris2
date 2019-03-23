module TTImp.Elab.Binders

import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Unify
import Core.TT
import Core.Value

import TTImp.Elab.Check
import TTImp.TTImp

%default covering

export
checkPi : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          {auto e : Ref EST (EState vars)} ->
          RigCount -> ElabInfo -> Env Term vars -> 
          FC -> 
          RigCount -> PiInfo -> (n : Name) -> 
          (argTy : RawImp) -> (retTy : RawImp) ->
          (expTy : Maybe (Glued vars)) ->
          Core (Term vars, Glued vars)
checkPi rig elabinfo env fc rigf info n argTy retTy expTy
    = do (tyv, tyt) <- check Rig0 (nextLevel elabinfo) env argTy 
                             (Just (gType fc))
         let env' : Env Term (n :: _) = Pi rigf info tyv :: env
         (scopev, scopet) <- 
            inScope (\e' => 
              check {e=e'} Rig0 (nextLevel elabinfo) env' retTy (Just (gType fc)))
         checkExp rig env fc (Bind fc n (Pi rigf info tyv) scopev) (gType fc) expTy

findLamRig : {auto c : Ref Ctxt Defs} ->
             Maybe (Glued vars) -> Core RigCount
findLamRig Nothing = pure RigW
findLamRig (Just expty)
    = do tynf <- getNF expty
         case tynf of
              NBind _ _ (Pi c _ _) sc => pure c
              _ => pure RigW

inferLambda : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto e : Ref EST (EState vars)} ->
              RigCount -> ElabInfo -> Env Term vars -> 
              FC -> 
              RigCount -> PiInfo -> (n : Name) -> 
              (argTy : RawImp) -> (scope : RawImp) ->
              (expTy : Maybe (Glued vars)) ->
              Core (Term vars, Glued vars)
inferLambda rig elabinfo env fc rigl info n argTy scope expTy
    = do rigb <- findLamRig expTy
         ?doInferLambda

export
checkLambda : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto e : Ref EST (EState vars)} ->
              RigCount -> ElabInfo -> Env Term vars -> 
              FC -> 
              RigCount -> PiInfo -> (n : Name) -> 
              (argTy : RawImp) -> (scope : RawImp) ->
              (expTy : Maybe (Glued vars)) ->
              Core (Term vars, Glued vars)
checkLambda rig_in elabinfo env fc rigl info n argTy scope Nothing
    = let rig = if rig_in == Rig0 then Rig0 else Rig1 in
          inferLambda rig elabinfo env fc rigl info n argTy scope Nothing
checkLambda rig_in elabinfo env fc rigl info n argTy scope (Just expty_in)
                  -- (Just (NBind bfc bn (Pi c _ pty) sc))
    = do let rig = if rig_in == Rig0 then Rig0 else Rig1
         (tyv, tyt) <- check Rig0 (nextLevel elabinfo) env argTy (Just (gType fc))
         expty <- getTerm expty_in
         defs <- get Ctxt
         case expty of
              Bind bfc bn (Pi c _ pty) psc =>
                 do let rigb = min rigl c
                    let env' : Env Term (n :: _) = Lam rigb info tyv :: env
                    (scopev, scopet) <-
                       inScope (\e' =>
                          check {e=e'} rig (nextLevel elabinfo) env' scope 
                                (Just (gnf defs env' (renameTop n psc))))
                    checkExp rig env fc 
                             (Bind fc n (Lam rigb info tyv) scopev)
                             (gnf defs env 
                                  (Bind fc n (Pi rigb info tyv) !(getTerm scopet)))
                             (Just (gnf defs env
                                       (Bind fc bn (Pi rigb info pty) psc)))
              _ => inferLambda rig elabinfo env fc rigl info n argTy scope (Just expty_in)
