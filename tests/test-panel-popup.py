#!/usr/bin/python3
"""Check popup boundaries and click-away behavior in an isolated X11 session.

Without a compositor (#384) the popup is the menu alone: X draws a transparent
window black there, so the full-screen click-away surface blacked out the screen.
A click on the desktop or on a window, the selected one included, takes the
keyboard from the popup (dwm), and the popup closes and tells its owner.

With Picom (when installed) the popup is the transparent surface over the screen
below the panel, as before. Picom starting or stopping while the popup is open
switches it between the two, and dwm-window-thumb watch-compositor reports both.

A click on the panel is the panel's own business (its MouseArea, S11-03), not
checked here. This test used to check it, but against the window id of the
earlier showing: a popup gets a new X window each time it opens, so that check
passed whatever the click did.

The second popup takes the keyboard only while open (grabFocus bound to it, as
the overview's is). Qt does not close such a popup by itself when it loses the
keyboard, so it checks ClickAwayPopup's own dismissal.
"""
import os, select, shutil, subprocess, tempfile, time
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home()/'tmp')
temp_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='panel-popup-', dir=str(temp_root)) as temp:
 base=Path(temp); config=base/'config'; qml=config/'quickshell'; qml.mkdir(parents=True)
 runtime=base/'runtime'; runtime.mkdir(mode=0o700)
 shutil.copytree(repo/'config/quickshell/core',qml/'core')
 (qml/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
ShellRoot {
 PanelWindow { id: panel; implicitHeight: 30; anchors { top: true; left: true; right: true } color: "white"; exclusiveZone: 30 }
 ClickAwayPopup { id: plain; targetWindow: panel; open: false; popupX: 40; popupWidth: 280; popupHeight: 300; onDismissed: open = false; Rectangle { anchors.fill: parent; color: "red" } }
 ClickAwayPopup { id: late; targetWindow: panel; open: false; grabFocus: open; popupX: 40; popupWidth: 280; popupHeight: 300; onDismissed: open = false; Rectangle { anchors.fill: parent; color: "blue" } }
 IpcHandler { target: "test"
  function open(name: string): void { (name === "late" ? late : plain).open = true; }
  function state(name: string): string { const popup = name === "late" ? late : plain; return [popup.open, popup.visible, Compositor.running].join(" "); } }
}''')
 # The checkout's dwm-window-thumb, as the installed one is on PATH.
 env={**os.environ,'PATH':str(repo)+os.pathsep+os.environ.get('PATH',''),'XDG_RUNTIME_DIR':str(runtime),'HOME':str(base),'XDG_CONFIG_HOME':str(config),'XDG_DATA_HOME':str(base/'data'),'XDG_STATE_HOME':str(base/'state'),'QT_QPA_PLATFORM':'xcb','QT_QPA_PLATFORMTHEME':''}
 log=(base/'runtime.log').open('w+')
 procs=[]
 def start(*args):
  procs.append(subprocess.Popen(list(args),env=env,stdout=log,stderr=log)); return procs[-1]
 def stop(proc):
  if proc.poll() is None: proc.terminate()
  try: proc.wait(timeout=5)
  except subprocess.TimeoutExpired: proc.kill(); proc.wait()
 def run(*args): return subprocess.run(args,env=env,capture_output=True,text=True)
 def wait_for(check, what, timeout=5.0):
  deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   if check(): return
   time.sleep(.05)
  raise AssertionError(what)
 which='plain'
 def state():
  out=run('quickshell','ipc','call','test','state',which).stdout.split()
  return dict(zip(('open','visible','compositor'),(word=='true' for word in out))) if len(out)==3 else {}
 def geometries():
  ids=run('xdotool','search','--onlyvisible','--pid',str(shell.pid)).stdout.split()
  return [dict(line.split("=", 1) for line in run('xdotool','getwindowgeometry','--shell',wid).stdout.splitlines()) for wid in ids]
 def popup():
  found=[g for g in geometries() if g and int(g['HEIGHT'])!=30]
  return found[0] if len(found)==1 else None
 def click(x,y): run('xdotool','mousemove',str(x),str(y),'click','1').check_returncode()
 def open_popup():
  run('quickshell','ipc','call','test','open',which).check_returncode()
  wait_for(lambda: state().get('visible') and popup() is not None,'popup did not open')
  # dwm gives it the keyboard (#280) only after it is mapped.
  wait_for(lambda: run('xdotool','getwindowfocus').stdout.strip()==popup()['WINDOW'],'popup did not get the keyboard')
  return popup()
 watch_buf=[b'']
 def watch_line(watch, what, picom=None, timeout=5.0):
  # Bounded: a Picom that never takes the selection must fail, not hang.
  deadline=time.monotonic()+timeout
  while b'\n' not in watch_buf[0]:
   if picom is not None and picom.poll() is not None: raise AssertionError('%s: Picom exited with status %s'%(what,picom.returncode))
   left=deadline-time.monotonic()
   if left<=0: raise AssertionError('%s: timed out'%what)
   if select.select([watch.stdout],[],[],min(left,.1))[0]:
    chunk=os.read(watch.stdout.fileno(),4096)
    if not chunk: raise AssertionError('%s: watch-compositor exited'%what)
    watch_buf[0]+=chunk
  line,watch_buf[0]=watch_buf[0].split(b'\n',1)
  return line.decode().strip()
 def assert_dismissed(what):
  wait_for(lambda: (lambda s: s.get('open') is False and s.get('visible') is False)(state()),what)
 def assert_menu_sized(g):
  assert (int(g['X']),int(g['Y']),int(g['WIDTH']),int(g['HEIGHT']))==(40,30,280,300),"Without a compositor the popup is not the menu alone: %r"%g
 def assert_surface(g):
  assert int(g['Y'])==int(panel['Y'])+int(panel['HEIGHT']),"Popup covers the panel"
  assert int(g['X'])==int(panel['X']) and g['WIDTH']==panel['WIDTH'] and int(g['HEIGHT'])==screen_h-30,"With a compositor the popup is not the full surface: %r"%g
 def check_clicks(surface):
  g=open_popup(); (assert_surface if surface else assert_menu_sized)(g)
  click(100,100); time.sleep(.2)
  assert state()['open'] and state()['visible'],"Content click dismissed popup"
  click(700,500); assert_dismissed("Outside click did not dismiss popup")
 screen_h=int(run('xdotool','getdisplaygeometry').stdout.split()[1])
 wm=start(str(repo/'dwm'))
 shell=start('quickshell','--no-duplicate')
 try:
  wait_for(lambda: state()!={},'IPC unavailable',10)
  panel=next(g for g in geometries() if g and int(g['HEIGHT'])==30)

  # No compositor: the menu alone, and a desktop click closes it (dwm, #384).
  assert not state()['compositor']
  for which in ('plain','late'): check_clicks(False)
  which='plain'

  # A click on a window closes it too, the selected window included: dwm takes
  # that click while the popup has the keyboard.
  feh=None
  if shutil.which('feh'):
   picture=base/'picture.ppm'; picture.write_bytes(b'P6 64 64 255\n'+bytes([0,90,160])*64*64)
   feh=start('feh','--title','popup-test-client',str(picture))
   wait_for(lambda: run('xdotool','search','--onlyvisible','--name','popup-test-client').returncode==0,'feh did not map')
   client=run('xdotool','search','--onlyvisible','--name','popup-test-client').stdout.split()[0]
   wait_for(lambda: run('xdotool','getwindowfocus').stdout.strip()==client,'feh is not the selected window')
   cg=dict(line.split("=",1) for line in run('xdotool','getwindowgeometry','--shell',client).stdout.splitlines())
   cx,cy=int(cg['X'])+int(cg['WIDTH'])-20,int(cg['Y'])+int(cg['HEIGHT'])-20
   for which in ('plain','late','plain'):
    open_popup(); click(cx,cy); assert_dismissed("A click on the selected window did not dismiss popup")
    wait_for(lambda: run('xdotool','getwindowfocus').stdout.strip()==client,'the clicked window did not get the keyboard back')
   which='plain'
  else:
   print('SKIP: feh is unavailable; the click on a window is not checked')

  if shutil.which('picom'):
   watch=subprocess.Popen([str(repo/'dwm-window-thumb'),'watch-compositor'],env=env,stdout=subprocess.PIPE,stderr=log)
   procs.append(watch)
   what="watch-compositor did not report no compositor"; assert watch_line(watch,what)=='compositor 0',what
   (base/'picom.conf').write_text('backend = "xrender";\n')
   picom=start('picom','--config',str(base/'picom.conf'))
   what="watch-compositor did not report Picom starting"; assert watch_line(watch,what,picom)=='compositor 1',what
   wait_for(lambda: state().get('compositor'),'the shell did not see Picom start')
   check_clicks(True)
   # Picom stopping while the popup is open: the menu alone, still open, still closes.
   g=open_popup(); assert_surface(g)
   stop(picom)
   what="watch-compositor did not report Picom stopping"; assert watch_line(watch,what)=='compositor 0',what
   wait_for(lambda: not state()['compositor'] and popup() is not None and int(popup()['WIDTH'])==280,'the popup did not shrink to the menu when Picom stopped')
   assert_menu_sized(popup()); assert state()['open'] and state()['visible']
   click(700,500); assert_dismissed("Outside click did not dismiss popup after Picom stopped")
   # And Picom starting while it is open: the full surface again.
   open_popup()
   picom=start('picom','--config',str(base/'picom.conf'))
   what="watch-compositor did not report Picom starting again"; assert watch_line(watch,what,picom)=='compositor 1',what
   wait_for(lambda: state().get('compositor') and popup() is not None and int(popup()['WIDTH'])==int(panel['WIDTH']),'the popup did not cover the screen when Picom started')
   assert_surface(popup()); assert state()['open'] and state()['visible']
   click(700,500); assert_dismissed("Outside click did not dismiss popup after Picom started")
   stop(picom); stop(watch)
  else:
   print('SKIP: picom is unavailable; the compositor case is not checked')
  assert wm.poll() is None and shell.poll() is None
  print('Popup is the menu alone without a compositor and the full surface with one; content, desktop, and window click behavior: PASS')
 finally:
  for proc in reversed(procs): stop(proc)
  log.seek(0); print(log.read()); log.close()
