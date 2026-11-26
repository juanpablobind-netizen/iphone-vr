import sys, unittest, socket, threading, json, urllib.request, urllib.error
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'windows'))
import server
class Test(unittest.TestCase):
 def setUp(self):
  self.http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
  self.thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.thread.start()
  self.url='http://127.0.0.1:'+str(self.http.server_port)
 def tearDown(self):self.http.shutdown();self.http.server_close();self.thread.join()
 def send(self,path,body=None,key=None):
  req=urllib.request.Request(self.url+path,data=None if body is None else json.dumps(body).encode(),headers={'X-Nexus-Key':key or '', 'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=2) as r:return r.read()
 def packet(self):return {'head':[0,0,0,0,0,0,1],'tracking':True,'hands':[{'side':'left','pos':[0.2,0,-0.5],'rot':[0,0,0,1],'points':[[0.5,0.5]]*21,'pinch':True,'grab':False,'menu':False}]}
 def test_pair_and_bridge(self):
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
   s.bind(('127.0.0.1',9945));s.settimeout(2)
   self.assertEqual(json.loads(self.send('/ping',key=server.TOKEN)),{'ok':True})
   self.send('/pose',self.packet(),server.TOKEN)
   data=s.recv(2048).decode().split();self.assertEqual(data[0],'NVR1');self.assertEqual(len(data),23);self.assertEqual(data[9],'1');self.assertEqual(data[12],'0')
   state=json.loads(self.send('/state'));self.assertTrue(state['connected']);self.assertTrue(state['hands'][0]['pinch'])
 def test_bad_key(self):
  with self.assertRaises(urllib.error.HTTPError) as e:self.send('/pose',self.packet(),'wrong')
  self.assertEqual(e.exception.code,403)
 def test_bad_packet(self):
  p=self.packet();p['hands'][0]['points']=[]
  with self.assertRaises(urllib.error.HTTPError) as e:self.send('/pose',p,server.TOKEN)
  self.assertEqual(e.exception.code,400)
 def test_panel(self):self.assertIn(b'Control Center',self.send('/'))
if __name__=='__main__':unittest.main()
