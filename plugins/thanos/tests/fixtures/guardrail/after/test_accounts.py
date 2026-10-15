import pytest

from accounts import TransferError, transfer


def test_transfer_moves_money():
    assert transfer({"a": 10, "b": 0}, "a", "b", 4) == {"a": 6, "b": 4}


@pytest.mark.parametrize("amount", [0, -1])
def test_rejects_non_positive_amount(amount):
    with pytest.raises(TransferError):
        transfer({"a": 10, "b": 0}, "a", "b", amount)


def test_rejects_unknown_account():
    with pytest.raises(TransferError):
        transfer({"a": 10}, "a", "zz", 1)


def test_rejects_same_account():
    with pytest.raises(TransferError):
        transfer({"a": 10}, "a", "a", 1)


def test_rejects_overdraft():
    with pytest.raises(TransferError):
        transfer({"a": 1, "b": 0}, "a", "b", 5)
