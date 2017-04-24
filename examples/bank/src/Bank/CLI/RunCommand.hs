module Bank.CLI.RunCommand
  ( runCLICommand
  ) where

import Control.Monad (void)
import Database.Persist.Sqlite

import Eventful

import Bank.Aggregates.Account
import Bank.Aggregates.Customer
import Bank.CLI.Options
import Bank.CLI.Store
import Bank.Commands
import Bank.Events

runCLICommand :: ConnectionPool -> CLICommand -> IO ()
runCLICommand pool (CreateCustomerCLI createCommand) = do
  uuid <- uuidNextRandom
  putStr "Attempting to create customer with UUID: "
  print uuid
  let command = CreateCustomer' createCommand
  void $ runDB pool $ commandStoredAggregate cliEventStore customerAggregate uuid command
runCLICommand pool (ViewAccountCLI uuid) = do
  (state, _) <- runDB pool $
    getLatestProjection cliEventStore accountProjection uuid
  printJSONPretty state
runCLICommand pool (OpenAccountCLI openCommand) = do
  uuid <- uuidNextRandom
  putStr "Attempting to open account with UUID: "
  print uuid
  let command = OpenAccount' openCommand
  void $ runDB pool $ commandStoredAggregate cliEventStore accountAggregate uuid command
runCLICommand pool (TransferToAccountCLI sourceId amount targetId) = do
  putStrLn $ "Starting transfer from acccount " ++ show sourceId ++ " to " ++ show targetId

  -- TODO: Put this in a proper process manager or saga.

  transferId <- uuidNextRandom
  let startCommand = TransferToAccount' $ TransferToAccount transferId sourceId amount targetId
  startResult <- runDB pool $ commandStoredAggregate cliEventStore accountAggregate sourceId startCommand
  case startResult of
    [AccountTransferRejected' (AccountTransferRejected _ reason)] -> print reason
    _ -> do
      let acceptCommand = AcceptTransfer' $ AcceptTransfer transferId sourceId amount
      void $ runDB pool $ commandStoredAggregate cliEventStore accountAggregate targetId acceptCommand
      let
        finalEvent =
          AccountTransferCompleted' $ AccountTransferCompleted transferId
      void $ runDB pool $ storeEvents cliEventStore AnyVersion sourceId [finalEvent]
      runCLICommand pool (ViewAccountCLI sourceId)
      runCLICommand pool (ViewAccountCLI targetId)

-- cliGloballyOrderedEventStore :: (MonadIO m) => GloballyOrderedEventStore JSONString (SqlPersistT m)
-- cliGloballyOrderedEventStore = sqlGloballyOrderedEventStore defaultSqlEventStoreConfig
