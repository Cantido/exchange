defmodule Exchange.AccountTest do
  use Exchange.EventStoreCase
  alias Exchange.Account
  alias Exchange.Account.Commands.{
    CreateAccount,
    DebitAccount
  }
  alias Exchange.Account.Events.{
    AccountCreated,
    AccountDebited
  }
  alias Commanded.Aggregates.Aggregate
  import Commanded.Assertions.EventAssertions
  doctest Exchange.Account

  test "create_account" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "my account :)"})

    assert_receive_event(Exchange.Commanded, AccountCreated, fn event ->
      assert event.account_id == "my account :)"
    end)
  end

  test "debit account" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "debit-account-id"})
    :ok = Exchange.Commanded.dispatch(%DebitAccount{account_id: "debit-account-id", amount: 100, asset: "XLM"})

    assert_receive_event(Exchange.Commanded, AccountDebited, fn event ->
      assert event.account_id == "debit-account-id"
      assert event.amount == 100
      assert event.asset == "XLM"
    end)
  end
end
