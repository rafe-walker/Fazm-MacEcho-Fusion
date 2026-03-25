---
name: telegram
description: Send and receive Telegram messages for the user. Handles setup (one-time auth), sending, and reading messages. Use when user says "connect Telegram", "send a Telegram message", "message X on Telegram", or "read my Telegram messages".
---

# Telegram Integration

Send and receive Telegram messages as the user. No bots, no browser — pure API over the network.

**IMPORTANT: NEVER use Playwright or browser automation for Telegram.** Always use the telethon Python API below — it's faster, more reliable, and works without a browser. Run the Python scripts via the Bash tool.

## Before You Start

### Check if already connected

```python
import asyncio, os
from telethon import TelegramClient

api_id = 611335
api_hash = 'd524b414d21f4d37f08684c1df41ac9c'
session_path = os.path.expanduser('~/.fazm/telegram.session')

async def check():
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    if await client.is_user_authorized():
        me = await client.get_me()
        print(f"CONNECTED as {me.first_name} ({me.phone})")
    else:
        print("NOT_CONNECTED")
    await client.disconnect()

asyncio.run(check())
```

If `CONNECTED`, skip to "Sending Messages" below. If `NOT_CONNECTED`, run setup.

### Install telethon if missing

```bash
pip3 install telethon 2>/dev/null
```

## Setup (one-time per user)

### Getting the user's phone number

The user's phone number may already be available:
- Check Fazm's user profile / account settings
- Check macOS Contacts for the user's own card: `contacts -H | head -5`
- Ask the user directly — must include country code (e.g. +1 for US)

**The user does NOT need Telegram installed.** Telethon works purely over the network. If they already have Telegram on any device, the code arrives there. If they've never used Telegram, the code arrives via SMS and telethon creates their account automatically.

### Step 1: Send code and auto-retrieve it

Once you have the phone number, send the code, then immediately read it yourself. **Do NOT ask the user for the code** — retrieve it automatically.

```python
async def request_code(phone):
    os.makedirs(os.path.expanduser('~/.fazm'), exist_ok=True)
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    result = await client.send_code_request(phone)
    with open('/tmp/telegram_code_hash.txt', 'w') as f:
        f.write(result.phone_code_hash)
    with open('/tmp/telegram_phone.txt', 'w') as f:
        f.write(phone)
    await client.disconnect()
    return result

asyncio.run(request_code('+1XXXXXXXXXX'))
```

### Step 2: Read the code automatically

The code arrives either via Telegram or SMS. Read it without user involvement:

**Method 1 — SMS (macOS Messages DB):** If the code arrives via SMS (user has no Telegram sessions):
```bash
sqlite3 ~/Library/Messages/chat.db "SELECT text FROM message WHERE text LIKE '%code%' OR text LIKE '%Telegram%' ORDER BY date DESC LIMIT 1;"
```

**Method 2 — Telegram notification (macOS):** If the user has Telegram on their Mac, the code appears as a macOS notification. Use macos-use MCP to read it, or check the Telegram app/web via Playwright.

**Method 3 — Telegram Web:** If a Telegram Web tab is open, navigate to `https://web.telegram.org/a/#777000` (Telegram's system account) and read the code from the snapshot. The code is a 5-digit number in a message like "Login code: XXXXX".

Pick whichever method is available. Try Method 2 or 3 first (faster), fall back to Method 1.

### Step 3: Sign in with the code

```python
async def sign_in(code):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    phone = open('/tmp/telegram_phone.txt').read().strip()
    phone_code_hash = open('/tmp/telegram_code_hash.txt').read().strip()
    try:
        await client.sign_in(phone, code, phone_code_hash=phone_code_hash)
    except Exception as e:
        if 'SessionPasswordNeededError' in str(type(e)):
            raise  # Ask user for 2FA password, then: await client.sign_in(password=pwd)
        raise
    me = await client.get_me()
    print(f"CONNECTED as {me.first_name} (ID: {me.id}, phone: {me.phone})")
    await client.send_message('me', 'Fazm connected to Telegram successfully!')
    await client.disconnect()

asyncio.run(sign_in('CODE'))
```

If `SessionPasswordNeededError`: this is the ONLY case where you need to ask the user — for their Telegram 2FA password.

Tell the user: "You're connected! I sent a confirmation to your Telegram Saved Messages."

**The user does nothing. Zero steps. The agent handles everything.**

## Sending Messages

Session persists — no re-auth needed after setup.

```python
async def send_message(recipient, message):
    """
    recipient can be:
    - 'me' for Saved Messages
    - '@username' for a Telegram username
    - '+1234567890' for a phone number (must be in their contacts)
    - A name like 'Alex Kravtsov' (resolved via dialog search)
    """
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()

    if recipient.startswith('@') or recipient.startswith('+') or recipient == 'me':
        await client.send_message(recipient, message)
    else:
        # Search by name in user's chats
        found = False
        async for dialog in client.iter_dialogs(limit=200):
            if recipient.lower() in dialog.name.lower():
                await client.send_message(dialog.entity, message)
                found = True
                break
        if not found:
            print(f"ERROR: Could not find '{recipient}' in Telegram chats")
            await client.disconnect()
            return

    print(f"SENT to {recipient}")
    await client.disconnect()

asyncio.run(send_message('RECIPIENT', 'MESSAGE'))
```

## Reading Messages

```python
async def read_messages(chat, limit=10):
    """Read recent messages from a chat. Chat can be a name, username, or 'me'."""
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()

    entity = chat
    if not (chat.startswith('@') or chat.startswith('+') or chat == 'me'):
        async for dialog in client.iter_dialogs(limit=200):
            if chat.lower() in dialog.name.lower():
                entity = dialog.entity
                break

    messages = []
    async for msg in client.iter_messages(entity, limit=limit):
        sender = msg.sender.first_name if msg.sender else "Unknown"
        messages.append(f"{sender}: {msg.text}")

    await client.disconnect()
    return messages

msgs = asyncio.run(read_messages('CHAT', 10))
for m in msgs:
    print(m)
```

## Listing Chats

```python
async def list_chats(limit=50):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()
    async for dialog in client.iter_dialogs(limit=limit):
        print(f"{dialog.name} (ID: {dialog.entity.id}, unread: {dialog.unread_count})")
    await client.disconnect()

asyncio.run(list_chats())
```

## Important Notes

- **No Telegram app required.** Works without Telegram installed. Code arrives via SMS if user has no Telegram sessions.
- **Session security.** `~/.fazm/telegram.session` grants full account access. Never expose or log it.
- **Rate limits.** Telegram throttles automated sends. Don't send more than ~30 messages/minute.
- **Entity caching.** First time sending to a user by ID may fail. Always resolve via `iter_dialogs()` first.
- **FloodWaitError.** If you hit rate limits, wait the number of seconds in the error before retrying.
