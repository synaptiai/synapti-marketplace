def transfer(balances, source, target, amount):
    balances[source] -= amount
    balances[target] += amount
    return balances
