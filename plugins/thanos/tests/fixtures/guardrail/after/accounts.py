class TransferError(Exception):
    pass


def transfer(balances, source, target, amount):
    if amount <= 0:
        raise TransferError("amount must be positive")
    if source not in balances or target not in balances:
        raise TransferError("unknown account")
    if source == target:
        raise TransferError("source and target must differ")
    if balances[source] < amount:
        raise TransferError("insufficient funds")
    balances[source] -= amount
    balances[target] += amount
    return balances
