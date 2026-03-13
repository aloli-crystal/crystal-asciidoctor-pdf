_fr", text="# crystal-asciidoctor-pdf

Un convertisseur AsciiDoc vers PDF pour Crystal, basé sur `crystal-asciidoctor` pour le parsing et `crystal-pdf` pour la génération du PDF.

## Installation

1.  Ajoutez cette dépendance à votre fichier `shard.yml` :

    ```yaml
    dependencies:
      crystal-asciidoctor-pdf:
        github: aloli/crystal-asciidoctor-pdf
    ```

2.  Exécutez `shards install`

## Utilisation

```crystal
require "crystal-asciidoctor-pdf"

input = "== Mon Document\n\nCeci est un test."
doc = Asciidoctor.load(input)
AsciidoctorPDF::Converter.new.convert(doc)
```

## Ligne de commande

Ce shard fournit également un exécutable `asciidoctor-pdf` :

```bash
asciidoctor-pdf mon_document.adoc
```

## Développement

Pour contribuer, clonez le dépôt et exécutez `shards install`.
Les tests peuvent être lancés avec `crystal spec`.

## Contribuer

1.  Forkez le projet ( https://github.com/aloli/crystal-asciidoctor-pdf/fork )
2.  Créez votre branche de fonctionnalité (`git checkout -b ma-nouvelle-fonctionnalite`)
3.  Commitez vos changements (`git commit -am 'Ajouter une nouvelle fonctionnalité'`)
4.  Poussez vers la branche (`git push origin ma-nouvelle-fonctionnalite`)
5.  Créez une nouvelle Pull Request

## Contributeurs

-   [papilip](https://github.com/papilip) - créateur et mainteneur
"
