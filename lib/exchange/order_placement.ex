defmodule Exchange.OrderPlacement do
  use Commanded.ProcessManagers.ProcessManager,
    application: Exchange.Commanded,
    name: "Exchange.OrderPlacement"

  # 0. order process started -> lock funds
  # 1. funds locked -> place order
  # 2. trade executed -> update account balances

  alias Exchange.Account.Commands.{
    DebitAccount,
    LockFunds,
    UnlockFunds,
    DeductLockedFunds
  }
  alias Exchange.Account.Events.{
    LockedFundsDeducted,
    FundsLocked,
    FundsUnlocked
  }

  alias Exchange.Orderbook.PlaceOrder

  alias Exchange.Orderbook.{
    OrderRequested,
    OrderFilled,
    OrderExpired
  }

  defstruct [
    :account_id,
    :symbol,
    :base_asset,
    :quote_asset,
    :order_id,
    :type,
    :side,
    :time_in_force,
    :price,
    :stop_price,
    :quantity,
    :timestamp
  ]

  def interested?(%OrderRequested{order_id: order_id}) do
    {:start!, order_id}
  end

  def interested?(%FundsLocked{order_id: order_id}) do
    {:continue!, order_id}
  end

  def interested?(%OrderFilled{order_id: order_id}) do
    {:continue!, order_id}
  end

  def interested?(%LockedFundsDeducted{order_id: order_id}) do
    {:stop, order_id}
  end

  def interested?(%FundsUnlocked{order_id: order_id}) do
    {:stop, order_id}
  end

  def handle(
    %__MODULE__{},
    %OrderRequested{
      account_id: account_id,
      order_id: order_id,
      price: price,
      quantity: quantity,
      side: side
    } = command
  ) do
    amount =
      case side do
        :buy -> price
        :sell -> quantity
      end
    %LockFunds{account_id: account_id, order_id: order_id, amount: amount}
  end

  def handle(%__MODULE__{} = pm, %FundsLocked{}) do
    %PlaceOrder{
      symbol: pm.symbol,
      order_id: pm.order_id,
      type: pm.type,
      side: pm.side,
      time_in_force: pm.time_in_force,
      price: pm.price,
      stop_price: pm.stop_price,
      quantity: pm.quantity,
      timestamp: pm.timestamp
    }
  end

  def handle(%__MODULE__{account_id: account_id} = pm, %OrderFilled{order_id: order_id}) do
    debit_amount =
      case pm.side do
        :buy -> pm.quantity
        :sell -> pm.price
      end
    [
      %DeductLockedFunds{account_id: account_id, order_id: order_id},
      %DebitAccount{account_id: account_id, amount: debit_amount}
    ]
  end

  def handle(%__MODULE__{account_id: account_id}, %OrderExpired{order_id: order_id}) do
    %UnlockFunds{account_id: account_id, order_id: order_id}
  end

  def apply(%__MODULE__{} = pm, %OrderRequested{} = event) do
    %__MODULE__{pm |
      account_id: event.account_id,
      symbol: event.symbol,
      base_asset: event.base_asset,
      quote_asset: event.quote_asset,
      order_id: event.order_id,
      type: event.type,
      side: event.side,
      time_in_force: event.time_in_force,
      price: event.price,
      stop_price: event.stop_price,
      quantity: event.quantity,
      timestamp: event.timestamp
    }
  end
end
