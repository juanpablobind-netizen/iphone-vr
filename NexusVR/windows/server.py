import argparse, json, math, secrets, socket, threading, time, hmac, io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE = Path(__file__).parent
TOKEN = secrets.token_hex(4)
LOCK = threading.Lock()
STATE = {'hands': [], 'head': [], 'received': 0, 'tracking': False}
UDP = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
CAPTURE = False
REGION = None

def numbers(x, n, limit=100):
    return isinstance(x, list) and len(x) == n and all(type(v) in (int,float) and math.isfinite(v) and abs(v)<=limit for v in x)

def validate(body):
    if not isinstance(body, dict) or not numbers(body.get('head'),7): raise ValueError('head')
    hands = body.get('hands')
    if not isinstance(hands,list) or len(hands)>2: raise ValueError('hands')
    out=[]; sides=set()
    for hand in hands:
        if not isinstance(hand,dict): raise ValueError('hand')
        side=hand.get('side'); pos=hand.get('pos'); quat=hand.get('rot'); pts=hand.get('points')
        if side not in ('left','right') or side in sides or not numbers(pos,3,5) or not numbers(quat,4,1.01): raise ValueError('pose')
        if not isinstance(pts,list) or len(pts)!=21 or any(p is not None and not numbers(p,2,1.01) for p in pts): raise ValueError('points')
        if not all(type(hand.get(k)) is bool for k in ('pinch','grab','menu')): raise ValueError('buttons')
        sides.add(side); out.append({k:hand[k] for k in ('side','pos','rot','points','pinch','grab','menu')})
    return {'hands':out,'head':body['head'],'tracking':body.get('tracking') is True,'received':time.time()}

def bridge(s):
    # Localhost only; absence/timeout releases input in the driver.
    chunks=['NVR1']
    for side in ('left','right'):
        h=next((x for x in s['hands'] if x['side']==side),None) if s['tracking'] else None
        vals=[1,*h['pos'],*h['rot'],int(h['pinch']),int(h['grab']),int(h['menu'])] if h else [0,0,0,0,0,0,0,1,0,0,0]
        chunks.extend(str(v) for v in vals)
    UDP.sendto(' '.join(chunks).encode('ascii'),('127.0.0.1',9945))

def lan_ip():
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
            s.connect(('192.0.2.1',80)); return s.getsockname()[0]
    except OSError: return 'consulta ipconfig'

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def reply(self,code,data=b'',kind='application/json'):
        self.send_response(code); self.send_header('Content-Type',kind); self.send_header('Content-Length',str(len(data))); self.send_header('Cache-Control','no-store'); self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError): pass
    def authed(self): return hmac.compare_digest(self.headers.get('X-Nexus-Key',''),TOKEN)
    def do_GET(self):
        if self.path in ('/','/state'):
            if self.client_address[0]!='127.0.0.1': return self.reply(403)
            if self.path=='/': return self.reply(200,(BASE/'panel.html').read_bytes(),'text/html; charset=utf-8')
            with LOCK: s=dict(STATE)
            s.update({'connected':time.time()-s['received']<1,'ip':lan_ip(),'key':TOKEN,'capture':CAPTURE})
            return self.reply(200,json.dumps(s).encode())
        if not self.authed(): return self.reply(403)
        if self.path=='/ping': return self.reply(200,b'{"ok":true}')
        if self.path=='/frame' and CAPTURE:
            try:
                import mss
                from PIL import Image
                with mss.mss() as cap:
                    shot=cap.grab(REGION or cap.monitors[1]); im=Image.frombytes('RGB',shot.size,shot.rgb)
                im.thumbnail((1600,900)); stream=io.BytesIO(); im.save(stream,format='JPEG',quality=65)
                return self.reply(200,stream.getvalue(),'image/jpeg')
            except Exception: return self.reply(503)
        return self.reply(404)
    def do_POST(self):
        if self.path!='/pose': return self.reply(404)
        if not self.authed(): return self.reply(403)
        try:
            n=int(self.headers.get('Content-Length','0'))
            if not 0<n<=16000: return self.reply(413)
            self.connection.settimeout(3)
            s=validate(json.loads(self.rfile.read(n)))
        except (ValueError,TypeError,OSError,OverflowError): return self.reply(400)
        with LOCK:
            STATE.update(s); bridge(s)
        self.reply(200,b'{"ok":true}')

def main():
    global CAPTURE,REGION
    p=argparse.ArgumentParser(); p.add_argument('--port',type=int,default=8765); p.add_argument('--capture',action='store_true'); p.add_argument('--region',nargs=4,type=int,metavar=('X','Y','W','H')); args=p.parse_args()
    CAPTURE=args.capture
    if args.region:
        x,y,w,h=args.region
        if w<=0 or h<=0: p.error('Region inválida')
        REGION=dict(left=x,top=y,width=w,height=h)
    server=ThreadingHTTPServer(('0.0.0.0',args.port),Handler)
    print(f'NEXUS VR | iPhone: http://{lan_ip()}:{args.port} | clave: {TOKEN}\nPanel: http://127.0.0.1:{args.port}\nCtrl+C para detener. Usar solo red privada de confianza.',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
if __name__=='__main__': main()
