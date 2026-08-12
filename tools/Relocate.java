import me.lucko.jarrelocator.JarRelocator;
import me.lucko.jarrelocator.Relocation;
import java.io.File;
import java.util.*;
public class Relocate {
  public static void main(String[] a) throws Exception {
    // args: input.jar output.jar from.package to.package
    List<Relocation> rules = new ArrayList<>();
    rules.add(new Relocation(a[2], a[3]));
    new JarRelocator(new File(a[0]), new File(a[1]), rules).run();
    System.out.println("relocated " + a[2] + " -> " + a[3]);
  }
}
