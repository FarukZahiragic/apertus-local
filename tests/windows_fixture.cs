// Functional fixture only: tiny HTTP service and raw model bytes, not inference.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public class ApertusFixture {
    public static void Main(string[] args) {
        string arguments = Environment.GetEnvironmentVariable("APERTUS_FIXTURE_ARGUMENTS");
        if (!String.IsNullOrEmpty(arguments)) File.WriteAllLines(arguments, args);
        int port = 0;
        for (int i=0; i<args.Length-1; i++) if (args[i]=="--port") port=Int32.Parse(args[i+1]);
        string failure = Environment.GetEnvironmentVariable("APERTUS_FIXTURE_START_FAILURE");
        if (!String.IsNullOrEmpty(failure) && File.Exists(failure)) { Console.Error.WriteLine("fixture startup failure"); Environment.Exit(7); }
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        Console.Error.WriteLine("server listening on 127.0.0.1:" + port);
        while (true) {
            TcpClient client=listener.AcceptTcpClient();
            Task.Run(() => Handle(client));
        }
    }
    static void Handle(TcpClient client) {
        try {
            using(client) using(NetworkStream stream=client.GetStream()) {
                StreamReader reader=new StreamReader(stream, Encoding.UTF8, false, 4096, true);
                string line=reader.ReadLine();
                if (line==null) return;
                string path=line.Split(' ')[1];
                int length=0; long offset=0; bool range=false;
                while(!String.IsNullOrEmpty(line=reader.ReadLine())) {
                    if(line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) length=Int32.Parse(line.Substring(15).Trim());
                    if(line.StartsWith("Range: bytes=", StringComparison.OrdinalIgnoreCase)) {
                        offset=Int64.Parse(line.Substring(13).Split('-')[0]); range=true;
                        string requests=Environment.GetEnvironmentVariable("APERTUS_FIXTURE_REQUESTS");
                        if(!String.IsNullOrEmpty(requests)) File.AppendAllText(requests,line+"\n");
                    }
                }
                if(length>0) { char[] body=new char[length]; int count=0; while(count<length) { int n=reader.Read(body,count,length-count); if(n==0) break; count+=n; } }
                byte[] bytes; int status=200; string extra="";
                if(path.StartsWith("/model")) {
                    byte[] source=File.ReadAllBytes(Environment.GetEnvironmentVariable("APERTUS_FIXTURE_SOURCE"));
                    string corrupt=Environment.GetEnvironmentVariable("APERTUS_FIXTURE_CORRUPT");
                    if(!String.IsNullOrEmpty(corrupt) && File.Exists(corrupt)) source[0]^=1;
                    if(offset>=source.Length) { status=416; bytes=new byte[0]; }
                    else {
                        bytes=new byte[source.Length-offset]; Array.Copy(source,offset,bytes,0,bytes.Length);
                        if(range) { status=206; extra="Content-Range: bytes "+offset+"-"+(source.Length-1)+"/"+source.Length+"\r\n"; }
                    }
                } else {
                    string text="{\"status\":\"ok\"}";
                    if(path=="/completion") {
                        string marker=Environment.GetEnvironmentVariable("APERTUS_FIXTURE_COMPUTE_FAILURE");
                        if(!String.IsNullOrEmpty(marker) && File.Exists(marker)) { status=500; text="{\"error\":\"fixture compute error\"}"; }
                        else text="{\"content\":\"Hello\"}";
                    }
                    bytes=Encoding.UTF8.GetBytes(text);
                }
                byte[] header=Encoding.ASCII.GetBytes("HTTP/1.1 "+status+" Fixture\r\nContent-Length: "+bytes.Length+"\r\n"+extra+"Connection: close\r\n\r\n");
                stream.Write(header,0,header.Length); stream.Write(bytes,0,bytes.Length); stream.Flush();
            }
        } catch { /* tests may close port probes without sending HTTP */ }
    }
}
