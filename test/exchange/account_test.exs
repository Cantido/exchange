defmodule Exchange.AccountTest do
  use Exchange.EventStoreCase
  alias Exchange.Account
  alias Exchange.Account.Commands.{
    CreateAccount,
    DebitAccount,
    CreditAccount
  }
  alias Exchange.Account.Events.{
    AccountCreated,
    AccountDebited,
    AccountCredited
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

  test "can't create an account with a previously used ID" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "my account :)"})
    {:error, :account_already_exists} = Exchange.Commanded.dispatch(%CreateAccount{account_id: "my account :)"})
  end

  test "debit account" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "debit-account-id"})
    :ok = Exchange.Commanded.dispatch(%DebitAccount{account_id: "debit-account-id", amount: Money.new(100, :XLM)})

    assert_receive_event(Exchange.Commanded, AccountDebited, fn event ->
      assert event.account_id == "debit-account-id"
      assert event.amount |> Money.equals?(Money.new(100, :XLM))
    end)
  end

  test "credit account" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "credit-account-id"})
    :ok = Exchange.Commanded.dispatch(%DebitAccount{account_id: "credit-account-id", amount: Money.new(100, :XLM)})
    :ok = Exchange.Commanded.dispatch(%CreditAccount{account_id: "credit-account-id", amount: Money.new(100, :XLM)})

    assert_receive_event(Exchange.Commanded, AccountCredited, fn event ->
      assert event.account_id == "credit-account-id"
      assert event.amount |> Money.equals?(Money.new(100, :XLM))
    end)
  end

  test "can't credit an account when it doesn't have enough funds" do
    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: "credit-account-id"})
    {:error, :not_enough_funds} = Exchange.Commanded.dispatch(%CreditAccount{account_id: "credit-account-id", amount: Money.new(100, :XLM)})
  end
end
