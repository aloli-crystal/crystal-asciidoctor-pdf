require "../spec_helper"
require "file_utils"

# Spec d'intégration : conversion de PLUSIEURS fichiers en une seule
# invocation, p. ex. `crystal-asciidoctor-pdf *.adoc`. Régression : seul
# le premier fichier était converti, les autres ignorés silencieusement.
describe "CLI · conversion multi-fichiers" do
  binary = File.join(__DIR__, "..", "..", "bin", "crystal-asciidoctor-pdf")

  it "convertit TOUS les fichiers passés (chacun son <nom>.adoc.pdf)" do
    pending! "binaire absent : #{binary}" unless File::Info.executable?(binary)
    dir = File.tempname("capdf-multi")
    Dir.mkdir_p(dir)
    begin
      names = %w[un deux trois]
      names.each_with_index do |name, i|
        File.write(File.join(dir, "#{name}.adoc"), "= Doc #{name}\n\nContenu #{i}.\n")
      end
      inputs = names.map { |n| File.join(dir, "#{n}.adoc") }
      status = Process.run(binary, inputs,
        output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.exit_code.should eq 0
      names.each do |n|
        File.exists?(File.join(dir, "#{n}.adoc.pdf")).should be_true
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "refuse -o avec plusieurs fichiers (exit 1, pas de PDF unique)" do
    pending! "binaire absent : #{binary}" unless File::Info.executable?(binary)
    dir = File.tempname("capdf-multi-o")
    Dir.mkdir_p(dir)
    begin
      a = File.join(dir, "a.adoc")
      b = File.join(dir, "b.adoc")
      File.write(a, "= A\n\nx.\n")
      File.write(b, "= B\n\ny.\n")
      out_pdf = File.join(dir, "out.pdf")
      status = Process.run(binary, ["-o", out_pdf, a, b],
        output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.exit_code.should eq 1
      File.exists?(out_pdf).should be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "poursuit malgré un fichier manquant, avec exit non nul" do
    pending! "binaire absent : #{binary}" unless File::Info.executable?(binary)
    dir = File.tempname("capdf-multi-miss")
    Dir.mkdir_p(dir)
    begin
      ok = File.join(dir, "ok.adoc")
      File.write(ok, "= OK\n\nz.\n")
      missing = File.join(dir, "absent.adoc")
      status = Process.run(binary, [ok, missing],
        output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.exit_code.should eq 1
      # Le fichier valide est quand même converti.
      File.exists?(File.join(dir, "ok.adoc.pdf")).should be_true
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
