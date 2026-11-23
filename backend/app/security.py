"""Field encryption and keyed hashes (kit primitives, keys from settings). Parents' phone numbers are encrypted: minors' data."""

from functools import lru_cache

from regisse_kit import crypto as kit

from app.config import get_settings


@lru_cache
def _cipher(key: str) -> kit.FieldCipher:
    return kit.FieldCipher(key)


@lru_cache
def _hasher(key: str) -> kit.KeyedHasher:
    return kit.KeyedHasher(key)


def encrypt(plaintext: str) -> bytes:
    return _cipher(get_settings().field_encryption_key).encrypt(plaintext)


def decrypt(blob: bytes) -> str:
    return _cipher(get_settings().field_encryption_key).decrypt(blob)


def phone_hash(e164: str) -> str:
    return _hasher(get_settings().hash_key).phone(e164)
