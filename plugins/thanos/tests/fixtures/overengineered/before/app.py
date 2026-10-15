def place_order(user, items):
    total = sum(item["price"] * item["qty"] for item in items)
    return {"user": user["id"], "total": total}
