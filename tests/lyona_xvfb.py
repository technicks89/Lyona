"""The display an Xvfb started with -displayfd reports.

    import lyona_xvfb

    read_fd, write_fd = os.pipe()
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), ...], pass_fds=(write_fd,))
    os.close(write_fd)
    display = lyona_xvfb.read_display(read_fd)  # ":N"; closes read_fd

Xvfb writes the number and the newline in two writes. A single read can get
the number alone, and closing the pipe then fails the second write: Xvfb
exits with "Cannot write display number to fd N", and every client after it
finds no display. So read until the newline (or end of file), and close the
pipe only then.
"""
import os
import select
import time


def read_display(read_fd, seconds=10):
    """':N' from Xvfb's -displayfd pipe, read up to its newline; closes read_fd."""
    deadline = time.monotonic() + seconds
    data = b''
    try:
        while not data.endswith(b'\n'):
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([read_fd], [], [], left)[0]:
                raise AssertionError('Xvfb startup timed out (read %r)' % data)
            chunk = os.read(read_fd, 32)
            if not chunk:
                break  # Xvfb closed it (or exited): what it wrote is all there is
            data += chunk
    finally:
        os.close(read_fd)
    number = data.decode(errors='replace').strip()
    if not number.isdigit():
        raise AssertionError('Xvfb did not report a display (read %r)' % data)
    return ':' + number
