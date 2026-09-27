// A stand-in for Android's apksigner (sign / verify) built on the apksig
// library from Maven Central, for exporting APKs without the Android SDK.
import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class ApkSignerCli {
    public static void main(String[] a) throws Exception {
        if (a.length == 0 || a[0].equals("--version") || a[0].equals("version")) { System.out.println("0.9"); System.exit(0); }
        String ks = null, pass = "", alias = null, apk = null;
        for (int i = 1; i < a.length; i++) {
            switch (a[i]) {
                case "--ks": ks = a[++i]; break;
                case "--ks-pass": pass = a[++i]; break;
                case "--ks-key-alias": alias = a[++i]; break;
                case "--key-pass": ++i; break;
                case "--verbose": case "-v": break;
                default:
                    if (a[i].startsWith("--")) { if (i + 1 < a.length && !a[i + 1].startsWith("--") && i + 1 < a.length - 1) i++; }
                    else apk = a[i];
            }
        }
        if (pass.startsWith("pass:")) pass = pass.substring(5);
        File in = new File(apk);
        if (a[0].equals("verify")) {
            ApkVerifier.Result r = new ApkVerifier.Builder(in).build().verify();
            System.out.println("Verified: " + r.isVerified() + " (v1 " + r.isVerifiedUsingV1Scheme() + ", v2 " + r.isVerifiedUsingV2Scheme() + ")");
            for (Object e : r.getErrors()) System.err.println("ERROR: " + e);
            System.exit(r.isVerified() ? 0 : 1);
        }
        KeyStore store;
        try { store = KeyStore.getInstance("PKCS12"); try (FileInputStream f = new FileInputStream(ks)) { store.load(f, pass.toCharArray()); } }
        catch (Exception e) { store = KeyStore.getInstance("JKS"); try (FileInputStream f = new FileInputStream(ks)) { store.load(f, pass.toCharArray()); } }
        if (alias == null) alias = Collections.list(store.aliases()).get(0);
        PrivateKey key = (PrivateKey) store.getKey(alias, pass.toCharArray());
        List<X509Certificate> certs = new ArrayList<>();
        for (Certificate c : store.getCertificateChain(alias)) certs.add((X509Certificate) c);
        ApkSigner.SignerConfig cfg = new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();
        File out = new File(apk + ".signed");
        List<ApkSigner.SignerConfig> cfgs = new ArrayList<>();
        cfgs.add(cfg);
        new ApkSigner.Builder(cfgs).setInputApk(in).setOutputApk(out).setV1SigningEnabled(false).setV2SigningEnabled(true).build().sign();
        Files.move(out.toPath(), in.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Signed " + apk);
    }
}
