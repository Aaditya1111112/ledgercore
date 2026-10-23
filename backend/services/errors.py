"""Turn Oracle errors into clean API responses."""

# Our package error codes -> HTTP status
BUSINESS_ERRORS = {
    20001: 400,  # invalid amount
    20002: 404,  # account or customer not found
    20003: 409,  # account not ACTIVE
    20004: 409,  # insufficient funds
    20005: 400,  # transfer to same account
    20006: 400,  # invalid input
}


class ApiError(Exception):
    """Raised by routes for bad requests found before calling the database."""

    def __init__(self, message, status=400):
        super().__init__(message)
        self.message = message
        self.status = status


def parse_oracle_error(code, message):
    """Return (http_status, body) for an Oracle error code and message.

    Business errors (ORA-20001 to ORA-20006) are shown to the user.
    Anything else is a system error: the details are hidden.
    """
    if code in BUSINESS_ERRORS:
        # Message looks like "ORA-20004: Insufficient funds ...\nORA-06512: at ..."
        first_line = message.splitlines()[0] if message else ""
        if ": " in first_line:
            first_line = first_line.split(": ", 1)[1]
        return BUSINESS_ERRORS[code], {"error": first_line, "code": f"ORA-{code}"}
    return 500, {"error": "Database error. The operation was rolled back.", "code": f"ORA-{code:05d}"}
