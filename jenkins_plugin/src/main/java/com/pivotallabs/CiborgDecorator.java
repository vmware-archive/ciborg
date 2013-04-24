package com.pivotallabs;

import hudson.Extension;
import hudson.model.PageDecorator;
import net.sf.json.JSONObject;

import org.kohsuke.stapler.StaplerRequest;

@Extension
public class CiborgDecorator extends PageDecorator {
  public CiborgDecorator() {
    super(CiborgDecorator.class);
    load();
  }

  @Override
  public boolean configure(StaplerRequest req, JSONObject formData)
  throws FormException {
    save();
    return super.configure(req, formData);
  }
}