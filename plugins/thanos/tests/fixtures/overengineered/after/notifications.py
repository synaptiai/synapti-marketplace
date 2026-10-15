from abc import ABC, abstractmethod
import smtplib


class Notifier(ABC):
    """Base class for every notification channel."""

    def __init__(self, retries=3, timeout=10, priority="normal", template=None):
        self.retries = retries
        self.timeout = timeout
        self.priority = priority
        self.template = template

    @abstractmethod
    def send(self, recipient, message):
        ...

    def render(self, message):
        if self.template:
            return self.template.format(message=message)
        return message


class EmailNotifier(Notifier):
    def send(self, recipient, message):
        with smtplib.SMTP("localhost", timeout=self.timeout) as smtp:
            smtp.sendmail("shop@example.com", [recipient], self.render(message))


class SmsNotifier(Notifier):
    def send(self, recipient, message):
        raise NotImplementedError("SMS gateway not chosen yet")


class SlackNotifier(Notifier):
    def send(self, recipient, message):
        raise NotImplementedError("Slack webhook not configured yet")


class NotifierFactory:
    _registry = {"email": EmailNotifier, "sms": SmsNotifier, "slack": SlackNotifier}

    @classmethod
    def register(cls, name, notifier_cls):
        cls._registry[name] = notifier_cls

    @classmethod
    def create(cls, name, **options):
        return cls._registry[name](**options)


def build_notifier(name, **options):
    return NotifierFactory.create(name, **options)
