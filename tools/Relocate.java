import me.lucko.jarrelocator.JarRelocator;
import me.lucko.jarrelocator.Relocation;
import java.io.File;
import java.util.*;
public class Relocate {
  public static void main(String[] a) throws Exception {
    // args: input.jar output.jar  from1 to1 [from2 to2 ...]
    List<Relocation> rules = new ArrayList<>();
    for (int i = 2; i + 1 < a.length; i += 2) rules.add(new Relocation(a[i], a[i + 1]));
    new JarRelocator(new File(a[0]), new File(a[1]), rules).run();
    System.out.println("relocated " + rules.size() + " rule(s)");
  }
}
