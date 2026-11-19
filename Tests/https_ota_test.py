"""Actual Network.framework listener and generated TLS identities, on macOS."""
import http.client, json, pathlib, plistlib, selectors, socket, ssl, subprocess, sys, tempfile
from urllib.parse import urlsplit
with tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d); payload=bytes(range(256))*8192
    (root/'fixture.ipa').write_bytes(payload)
    proc=subprocess.Popen([sys.argv[1],str(root)],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    try:
        ready=selectors.DefaultSelector();ready.register(proc.stdout,selectors.EVENT_READ)
        assert ready.select(30), 'HTTPS listener not ready'
        address=json.loads(proc.stdout.readline()); url=urlsplit(address['manifest']);origin=url.hostname;port=url.port
        assert origin=='127.0.0.1' and url.scheme=='https'
        config=plistlib.loads((root/'trust.mobileconfig').read_bytes())
        ca=config['PayloadContent'][0]['PayloadContent']
        context=ssl.create_default_context(cadata=ssl.DER_cert_to_PEM_cert(ca))
        context.verify_flags |= ssl.VERIFY_X509_STRICT
        def request(path,method='GET',headers=None):
            c=http.client.HTTPSConnection(origin,port,context=context,timeout=10)
            c.request(method,path,headers=headers or {})
            response=c.getresponse();body=response.read();result=(response.status,dict(response.getheaders()),body)
            c.close();return result
        status,headers,data=request(url.path)
        assert status==200 and headers['Content-Type']=='application/xml' and int(headers['Content-Length'])==len(data)
        item=plistlib.loads(data)['items'][0];meta=item['metadata'];ipa=urlsplit(item['assets'][0]['url'])
        assert meta=={'bundle-identifier':'com.fixture.app','bundle-version':'123','kind':'software','title':'Fixture & <App>'}
        assert ipa.hostname==origin and ipa.port==port and ipa.scheme=='https'
        status,headers,body=request(ipa.path);assert status==200 and body==payload and int(headers['Content-Length'])==len(payload)
        for value,a,b in [('bytes=0-7',0,8),('bytes=100-',100,len(payload)),('bytes=-17',len(payload)-17,len(payload)),('bytes=5-99999999',5,len(payload))]:
            status,headers,body=request(ipa.path,headers={'Range':value})
            assert status==206 and body==payload[a:b] and int(headers['Content-Length'])==b-a
            assert headers['Content-Range']==f'bytes {a}-{b-1}/{len(payload)}'
            assert headers['Accept-Ranges']=='bytes' and headers['Content-Type']=='application/octet-stream'
        status,headers,body=request(ipa.path,'HEAD');assert status==200 and body==b'' and int(headers['Content-Length'])==len(payload)
        status,headers,body=request(url.path,'HEAD');assert status==200 and body==b'' and int(headers['Content-Length'])==len(data)
        status,headers,body=request(ipa.path,headers={'Range':f'bytes={len(payload)}-'})
        assert status==416 and body==b'' and headers['Content-Range']==f'bytes */{len(payload)}'
        assert request('/wrong/manifest.plist')[0]==404
        assert request(ipa.path,'POST')[0]==405
        status,headers,page=request(urlsplit(address['landing']).path)
        assert status==200 and b'Fixture &amp; &lt;App&gt;' in page
        for _ in range(20):assert request(url.path,'HEAD')[0]==200 # no retained-connection slot leak
        (root/'stop').touch();out,_=proc.communicate(timeout=10)
        assert proc.returncode==0 and 'STOPPED' in out
        with socket.socket() as c:assert c.connect_ex((origin,port))!=0
        print('PASS: actual generated-root TLS listener, CMS manifest metadata, full/HEAD/byte-range bodies, 416, route isolation, escaped landing, connection cleanup and stop')
    finally:
        if proc.poll() is None:proc.kill()
        proc.wait()
