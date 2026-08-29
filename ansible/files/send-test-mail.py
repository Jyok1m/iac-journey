#!/usr/bin/env python3
"""Send one test message through the local submission port with SASL.

Deliberately a normal-looking message. mail-tester scores content as well as
authentication, so a bare "test" body loses points to SpamAssassin rules that
have nothing to do with the mail server being correctly configured.
"""

import email.utils
import smtplib
import sys
from email.message import EmailMessage

with open(sys.argv[1]) as fh:
    sender, password, recipient = (line.strip() for line in fh.readlines()[:3])

msg = EmailMessage()
msg["From"] = f"Joachim Jasmin <{sender}>"
msg["To"] = recipient
msg["Subject"] = "Delivery configuration check for joachimjasmin.com"
msg["Date"] = email.utils.formatdate(localtime=True)
msg["Message-ID"] = email.utils.make_msgid(domain=sender.split("@")[1])
# A List-Unsubscribe header is one of the things content scoring looks for,
# and it costs nothing to be a well-behaved sender.
msg["List-Unsubscribe"] = f"<mailto:{sender}?subject=unsubscribe>"

msg.set_content(
    "Hello,\n\n"
    "This message was sent from the mail server for joachimjasmin.com to "
    "confirm that SPF, DKIM and DMARC are aligned and that the sending host "
    "presents the name its reverse record claims.\n\n"
    "No reply is needed.\n\n"
    "-- \n"
    "Joachim Jasmin\n"
    f"{sender}\n"
)
msg.add_alternative(
    "<html><body>"
    "<p>Hello,</p>"
    "<p>This message was sent from the mail server for joachimjasmin.com to "
    "confirm that SPF, DKIM and DMARC are aligned and that the sending host "
    "presents the name its reverse record claims.</p>"
    "<p>No reply is needed.</p>"
    f"<p>--<br>Joachim Jasmin<br>{sender}</p>"
    "</body></html>",
    subtype="html",
)

with smtplib.SMTP("127.0.0.1", 587, timeout=30) as smtp:
    smtp.ehlo()
    smtp.starttls()
    smtp.ehlo()
    smtp.login(sender, password)
    smtp.send_message(msg)

print(f"sent {msg['Message-ID']} from {sender} to {recipient}")
