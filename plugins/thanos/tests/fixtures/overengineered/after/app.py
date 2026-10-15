from notifications import build_notifier


def place_order(user, items):
    total = sum(item["price"] * item["qty"] for item in items)
    order = {"user": user["id"], "total": total}
    build_notifier("email").send(user["email"], f"Order confirmed: {total}")
    return order
